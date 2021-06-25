{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE RecordWildCards    #-}
{-# LANGUAGE TypeApplications   #-}
{-# LANGUAGE TypeFamilies       #-}
{-# LANGUAGE TypeOperators      #-}

module Plutus.PAB.Simulation where

import           Control.Monad                       (forM, forM_, void, when)
import           Control.Monad.Freer                 (Eff, Member, interpret,
                                                      type (~>))
import           Control.Monad.Freer.Error           (Error)
import           Control.Monad.Freer.Extras.Log      (LogMsg)
import           Control.Monad.IO.Class              (MonadIO (..))
import           Data.Aeson                          (FromJSON, Result (..),
                                                      ToJSON, encode, fromJSON)
import qualified Data.ByteString                     as BS
import qualified Data.Map.Strict                     as Map
import qualified Data.Monoid                         as Monoid
import qualified Data.Semigroup                      as Semigroup
import           Data.Text                           (Text)
import           Data.Text.Prettyprint.Doc           (Pretty (..), viaShow)
import           GHC.Generics                        (Generic)
import           Ledger
import           Ledger.Ada                          (adaSymbol, adaToken,
                                                      adaValueOf,
                                                      lovelaceValueOf)
import           Ledger.Constraints
import qualified Ledger.Constraints.OffChain         as Constraints
import qualified Ledger.Typed.Scripts                as Scripts
import           Ledger.Value                        as Value
import           Plutus.Contract                     hiding (when)
import qualified Plutus.Contracts.Core               as Aave
import           Plutus.Contracts.Currency           as Currency
import           Plutus.Contracts.Endpoints          (ContractResponse (..))
import qualified Plutus.Contracts.Endpoints          as Aave
import qualified Plutus.Contracts.FungibleToken      as FungibleToken
import qualified Plutus.Contracts.Oracle             as Oracle
import           Plutus.PAB.Effects.Contract         (ContractEffect (..))
import           Plutus.PAB.Effects.Contract.Builtin (Builtin, SomeBuiltin (..),
                                                      type (.\\))
import qualified Plutus.PAB.Effects.Contract.Builtin as Builtin
import           Plutus.PAB.Monitoring.PABLogMsg     (PABMultiAgentMsg)
import           Plutus.PAB.Simulator                (Simulation,
                                                      SimulatorEffectHandlers)
import qualified Plutus.PAB.Simulator                as Simulator
import           Plutus.PAB.Types                    (PABError (..))
import qualified Plutus.PAB.Webserver.Server         as PAB.Server
import           Plutus.V1.Ledger.Crypto             (getPubKeyHash, pubKeyHash)
import           Prelude                             hiding (init)
import           Wallet.Emulator.Types               (Wallet (..), walletPubKey)
import           Wallet.Types                        (ContractInstanceId)

wallets :: [Wallet]
wallets = [Wallet i | i <- [1 .. 4]]

testCurrencyNames :: [TokenName]
testCurrencyNames = ["MOGUS", "USD"]

toAsset :: TokenName -> AssetClass
toAsset tokenName =
   assetClass (scriptCurrencySymbol . FungibleToken.makeLiquidityPolicy $ tokenName) tokenName

testAssets :: [AssetClass]
testAssets = fmap toAsset testCurrencyNames

initContract :: Contract (Monoid.Last [Oracle.Oracle]) BlockchainActions Text ()
initContract = do
    ownPK <- pubKeyHash <$> ownPubKey
    let testCurrenciesValue = mconcat $ fmap (`assetClassValue` 1000) testAssets
        policyLookups = mconcat $
            fmap (Constraints.monetaryPolicy . FungibleToken.makeLiquidityPolicy . Prelude.snd . unAssetClass) testAssets
        adaValue = lovelaceValueOf amount
    forM_ wallets $ \w -> do
        let pkh = pubKeyHash $ walletPubKey w
            lookups = policyLookups
            tx = mustForgeValue testCurrenciesValue <> mustPayToPubKey pkh (adaValue <> testCurrenciesValue)
        when (pkh /= ownPK) $ do
            ledgerTx <- submitTxConstraintsWith @Scripts.Any lookups tx
            void $ awaitTxConfirmed $ txId ledgerTx
    oracles <- forM testAssets $ \asset -> do
        let oracleParams = Oracle.OracleParams
                { opFees   = 0
                , opSymbol = fst . unAssetClass $ asset
                , opToken  = snd . unAssetClass $ asset
                }
        oracle <- Oracle.startOracle oracleParams
        Oracle.updateOracle oracle oneAdaInLovelace
        pure oracle
    tell $ Monoid.Last $ Just oracles
  where
    amount = 1000000

data ContractIDs = ContractIDs { cidUser :: Map.Map Wallet ContractInstanceId, cidInfo :: ContractInstanceId }

activateContracts :: Simulation (Builtin AaveContracts) ContractIDs
activateContracts = do
    cidInit  <- Simulator.activateContract (Wallet 1) Init
    oracles  <- flip Simulator.waitForState cidInit $ \json -> case (fromJSON json :: Result (Monoid.Last [Oracle.Oracle])) of
                    Success (Monoid.Last (Just res)) -> Just res
                    _                                -> Nothing
    Simulator.logString @(Builtin AaveContracts) "Initialization finished."

    let params = fmap (\o -> Aave.CreateParams (Oracle.oAsset o) o) oracles
    cidStart <- Simulator.activateContract (Wallet 1) (AaveStart params)
    aa       <- flip Simulator.waitForState cidStart $ \json -> case (fromJSON json :: Result (Monoid.Last (Either Text Aave.Aave))) of
                    Success (Monoid.Last (Just (Right aa))) -> Just aa
                    _                                       -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Aave instance created: " ++ show aa

    cidInfo <- Simulator.activateContract (Wallet 1) $ AaveInfo aa

    cidUser <- fmap Map.fromList $ forM (tail wallets) $ \w -> do
        cid <- Simulator.activateContract w $ AaveUser aa
        Simulator.logString @(Builtin AaveContracts) $ "Aave user contract started for " ++ show w
        return (w, cid)

    pure $ ContractIDs cidUser cidInfo

runLendingPool :: IO ()
runLendingPool = void $ Simulator.runSimulationWith handlers $ do
    Simulator.logString @(Builtin AaveContracts) "Starting Aave PAB webserver on port 8080. Press enter to exit."
    shutdown <- PAB.Server.startServerDebug
    _ <- activateContracts
    Simulator.logString @(Builtin AaveContracts) "Aave PAB webserver started on port 8080. Initialization complete. Press enter to exit."
    _ <- liftIO getLine
    shutdown

runLendingPoolSimulation :: IO ()
runLendingPoolSimulation = void $ Simulator.runSimulationWith handlers $ do
    Simulator.logString @(Builtin AaveContracts) "Starting Aave PAB webserver on port 8080. Press enter to exit."
    shutdown <- PAB.Server.startServerDebug
    ContractIDs {..} <- activateContracts
    let userCid = cidUser Map.! Wallet 2
        sender = pubKeyHash . walletPubKey $ Wallet 2

    _  <-
        Simulator.callEndpointOnInstance userCid "deposit" $
            Aave.DepositParams { Aave.dpAsset = head testAssets, Aave.dpOnBehalfOf = sender, Aave.dpAmount = 400 }
    flip Simulator.waitForState userCid $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.UserContractState))) of
        Success (Monoid.Last (Just (ContractSuccess Aave.Deposited))) -> Just ()
        _                                                             -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Successful deposit"

    _  <-
        Simulator.callEndpointOnInstance userCid "withdraw" $
            Aave.WithdrawParams { Aave.wpAsset = head testAssets, Aave.wpUser = sender, Aave.wpAmount = 30 }
    flip Simulator.waitForState userCid $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.UserContractState))) of
        Success (Monoid.Last (Just (ContractSuccess Aave.Withdrawn))) -> Just ()
        _                                                             -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Successful withdraw"

    _  <-
        Simulator.callEndpointOnInstance userCid "provideCollateral" $
            Aave.ProvideCollateralParams { Aave.pcpUnderlyingAsset = head testAssets, Aave.pcpOnBehalfOf = sender, Aave.pcpAmount = 200 }
    flip Simulator.waitForState userCid $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.UserContractState))) of
        Success (Monoid.Last (Just (ContractSuccess Aave.CollateralProvided))) -> Just ()
        _                                                   -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Successful provideCollateral"

    _  <-
        Simulator.callEndpointOnInstance userCid "revokeCollateral" $
            Aave.RevokeCollateralParams { Aave.rcpUnderlyingAsset = head testAssets, Aave.rcpOnBehalfOf = sender, Aave.rcpAmount = 50 }
    flip Simulator.waitForState userCid $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.UserContractState))) of
        Success (Monoid.Last (Just (ContractSuccess Aave.CollateralRevoked))) -> Just ()
        _                                                   -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Successful revokeCollateral"

    let lenderCid = cidUser Map.! Wallet 3
    let lender = pubKeyHash . walletPubKey $ Wallet 3
    _  <-
        Simulator.callEndpointOnInstance lenderCid "deposit" $
            Aave.DepositParams { Aave.dpAsset = testAssets !! 1, Aave.dpOnBehalfOf = lender, Aave.dpAmount = 200 }
    flip Simulator.waitForState lenderCid $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.UserContractState))) of
        Success (Monoid.Last (Just (ContractSuccess Aave.Deposited))) -> Just ()
        _                                                             -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Successful deposit from lender"

    _  <-
        Simulator.callEndpointOnInstance userCid "borrow" $
            Aave.BorrowParams { Aave.bpAsset = testAssets !! 1, Aave.bpAmount = 35, Aave.bpOnBehalfOf = sender }
    flip Simulator.waitForState userCid $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.UserContractState))) of
        Success (Monoid.Last (Just (ContractSuccess Aave.Borrowed))) -> Just ()
        _                                                            -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Successful borrow"

    _  <-
        Simulator.callEndpointOnInstance userCid "repay" $
            Aave.RepayParams { Aave.rpAsset = testAssets !! 1, Aave.rpAmount = 25, Aave.rpOnBehalfOf = sender }
    flip Simulator.waitForState userCid $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.UserContractState))) of
        Success (Monoid.Last (Just (ContractSuccess Aave.Repaid))) -> Just ()
        _                                                          -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Successful repay"

    _ <- Simulator.callEndpointOnInstance cidInfo "fundsAt" sender
    v <- flip Simulator.waitForState cidInfo $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.InfoContractState))) of
            Success (Monoid.Last (Just (ContractSuccess (Aave.FundsAt v)))) -> Just v
            _                                                     -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Final user funds: " <> show v

    _ <- Simulator.callEndpointOnInstance cidInfo "fundsAt" lender
    v <- flip Simulator.waitForState cidInfo $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.InfoContractState))) of
            Success (Monoid.Last (Just (ContractSuccess (Aave.FundsAt v)))) -> Just v
            _                                                     -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Final lender funds: " <> show v

    _ <- Simulator.callEndpointOnInstance cidInfo "reserves" ()
    reserves <- flip Simulator.waitForState cidInfo $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.InfoContractState))) of
            Success (Monoid.Last (Just (ContractSuccess (Aave.Reserves reserves)))) -> Just reserves
            _                                                      -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Final reserves: " <> show reserves

    _ <- Simulator.callEndpointOnInstance cidInfo "poolFunds" ()
    v <- flip Simulator.waitForState cidInfo $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.InfoContractState))) of
            Success (Monoid.Last (Just (ContractSuccess (Aave.PoolFunds v)))) -> Just v
            _                                                       -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Final pool funds: " <> show v

    _ <- Simulator.callEndpointOnInstance cidInfo "users" ()
    v <- flip Simulator.waitForState cidInfo $ \json -> case (fromJSON json :: Result (Monoid.Last (ContractResponse Text Aave.InfoContractState))) of
            Success (Monoid.Last (Just (ContractSuccess (Aave.Users v)))) -> Just v
            _                                                   -> Nothing
    Simulator.logString @(Builtin AaveContracts) $ "Final users: " <> show v
    _ <- liftIO getLine
    shutdown

data AaveContracts =
      Init
    | AaveStart [Aave.CreateParams]
    | AaveInfo Aave.Aave
    | AaveUser Aave.Aave
    deriving (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

instance Pretty AaveContracts where
    pretty = viaShow

handleAaveContract ::
    ( Member (Error PABError) effs
    , Member (LogMsg (PABMultiAgentMsg (Builtin AaveContracts))) effs
    )
    => ContractEffect (Builtin AaveContracts)
    ~> Eff effs
handleAaveContract = Builtin.handleBuiltin getSchema getContract where
  getSchema = \case
    AaveUser _ -> Builtin.endpointsToSchemas @(Aave.AaveUserSchema .\\ BlockchainActions)
    AaveInfo _ -> Builtin.endpointsToSchemas @(Aave.AaveInfoSchema .\\ BlockchainActions)
    AaveStart _  -> Builtin.endpointsToSchemas @(Aave.AaveOwnerSchema .\\ BlockchainActions)
    Init          -> Builtin.endpointsToSchemas @Empty
  getContract = \case
    AaveInfo aave    -> SomeBuiltin $ Aave.infoEndpoints aave
    AaveUser aave    -> SomeBuiltin $ Aave.userEndpoints aave
    AaveStart params -> SomeBuiltin $ Aave.ownerEndpoint params
    Init             -> SomeBuiltin initContract

handlers :: SimulatorEffectHandlers (Builtin AaveContracts)
handlers =
    Simulator.mkSimulatorHandlers @(Builtin AaveContracts) []
    $ interpret handleAaveContract

oneAdaInLovelace :: Integer
oneAdaInLovelace = 1000000
