{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Spec.StableCoinTest
  ( tests,
  )
where

import Control.Monad (void)
import Control.Monad.Freer.Extras as Extras
import qualified Data.Map as Map
import Data.Text
import           Ledger    (pubKeyHash)
import qualified Ledger.Ada as Ada
import Ledger.Address (Address)
import qualified Ledger.Typed.Scripts as Scripts
import Ledger.Value (Value)
import Ledger.Value as Value
import Plutus.Contract
import Plutus.Contract.Test
import qualified Plutus.Contracts.CoinsStateMachine as CoinsMachine
import Plutus.Contracts.CoinsStateMachine (BankParam(..))
import qualified Plutus.Trace.Emulator as Trace
import qualified PlutusTx
import PlutusTx.Numeric (negate, one, zero)
import PlutusTx.Prelude
import qualified PlutusTx.Prelude as PlutusTx
import PlutusTx.Ratio as R
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit
import qualified Prelude
import Plutus.Contracts.Oracle.Core as Oracle
import qualified PlutusTx.Numeric  as P

oracleW1, w2 ,w3:: Wallet
oracleW1 = Wallet 1
w2 =       Wallet 2
w3 =       Wallet 3

stableCoinName :: TokenName
stableCoinName = "StableToken"

reserveCoinName :: TokenName
reserveCoinName = "ReserveToken"

oracleSymbol :: CurrencySymbol
oracleSymbol = "ff"

oracle :: Oracle
oracle = Oracle
            { oNftSymbol = oracleSymbol
            , oOperator  = pubKeyHash $ walletPubKey oracleW1
            , oFee       = 1
            }

bp :: BankParam
bp = CoinsMachine.BankParam
            { 
            stableCoinTokenName = stableCoinName,
            reserveCoinTokenName = reserveCoinName,
            minReserveRatio = P.zero,
            maxReserveRatio = 4 % 1,
            rcDefaultRate = 1,
            oracleParam = oracle
            }

address :: Address
address = Scripts.validatorAddress $ CoinsMachine.scriptInstance bp


reserveCoinsValue :: CoinsMachine.BankParam -> Integer -> Value
reserveCoinsValue bankParam@CoinsMachine.BankParam {reserveCoinTokenName} tokenAmount =
  let mpHash = Scripts.forwardingMonetaryPolicyHash $ CoinsMachine.scriptInstance bankParam
   in Value.singleton (Value.mpsSymbol mpHash) reserveCoinTokenName tokenAmount

stableCoinsValue :: CoinsMachine.BankParam -> Integer -> Value
stableCoinsValue bankParam@CoinsMachine.BankParam {stableCoinTokenName} tokenAmount =
  let mpHash = Scripts.forwardingMonetaryPolicyHash $ CoinsMachine.scriptInstance bankParam
   in Value.singleton (Value.mpsSymbol mpHash) stableCoinTokenName tokenAmount

initialAdaValue :: Value
initialAdaValue = Ada.lovelaceValueOf 100

oracleToken :: TokenName
oracleToken = TokenName emptyByteString

-- -- | The token that we are auctioning off.
-- theToken :: Value
-- theToken =
--     -- "ff" is not a valid MPS hash. But this doesn't matter because we
--     -- never try to forge any value of "ffff" using a script.
--     -- This currency is created by the initial transaction.
--     Value.singleton oracleSymbol oracleToken 1


-- -- | 'CheckOptions' that inclues 'theToken' in the initial distribution of wallet 1.
-- options :: CheckOptions
-- options =
--     let initialDistribution = defaultDist & over (at (Wallet 1) . _Just) ((<>) theToken)
--     in defaultCheckOptions & emulatorConfig . Trace.initialChainState .~ Left initialDistribution


tests :: TestTree
tests =
  testGroup
    "stablecoin"
    [ 
      checkPredicate "mint stablecoins"
          ( 
            -- (valueAtAddress address (== initialAdaValue))
              -- .&&. 
              assertNoFailedTransactions
              -- .&&. walletFundsChange w2 ((stableCoinsValue bp 100))
          )
      $ mintStableCoins 100
      
    --   checkPredicate "mint reservecoins"
    --     ( (valueAtAddress coinsMachineAddress (== initialAdaValue))
    --         .&&. assertNoFailedTransactions
    --         .&&. walletFundsChange w1 ((reserveCoinsValue bp 100) <> (negate initialAdaValue))
    --     )
    --     $ mintReserveCoins 100 1 1
        
    --     --Mint 10 stable coin, redeem 5 stable coin
    --     -- So value at address is 5 and user also have  stable coin with charge of 10 at rate 1:1
    -- , 
    --   checkPredicate "mint stablecoins redeem stablecoins"
    --     ( ( valueAtAddress coinsMachineAddress (== (Ada.lovelaceValueOf 5)))
    --         .&&. assertNoFailedTransactions
    --         .&&. walletFundsChange w1 ((stableCoinsValue bp 5) <> (negate (Ada.lovelaceValueOf 5)))
    --     )
    --     $ mintAndRedeemStableCoins 10 5 1 1
    -- ,    
    --   checkPredicate "mint reservecoins redeem reservecoins"
    --     ( ( valueAtAddress coinsMachineAddress (== (Ada.lovelaceValueOf 5)))
    --         .&&. assertNoFailedTransactions
    --         .&&. walletFundsChange w1 ((reserveCoinsValue bp 5) <> (negate (Ada.lovelaceValueOf 5)))
    --     )
    --     $ mintAndRedeemReserveCoins 10 5 1 1
    -- ,    
        -- checkPredicate "mint stablecoins try redeem more stablecoins than minted should fail"
        -- (  
        --    assertContractError CoinsMachine.endpoints (Trace.walletInstanceTag w1) (\_ -> True) "should throw insufficent funds"
        -- )
        -- $ mintAndRedeemStableCoins 10 15 1 1
        -- ,
        -- checkPredicate "mint reserve coins try redeem more reserve coins than minted should fail"
        -- (  
        --    assertContractError CoinsMachine.endpoints (Trace.walletInstanceTag w1) (\_ -> True) "should throw insufficent funds"
        -- )
        -- $ mintAndRedeemStableCoins 10 15 1 1
        
    ]



-- oracleTest :: Trace.EmulatorTrace ()
-- oracleTest = do
--     let op = OracleParams
--                 { opFees = 1_000_000
--                 , opSymbol = assetSymbol
--                 , opToken  = assetToken
--                 }

--     h1 <- activateContractWallet (Wallet 1) $ runOracle op
--     void $ Emulator.waitNSlots 1
--     oracle <- getOracle h1

--     void $ activateContractWallet (Wallet 2) $ checkOracle oracle

--     callEndpoint @"update" h1 1_500_000
--     void $ Emulator.waitNSlots 3

--     void $ activateContractWallet (Wallet 1) ownFunds'

initialise :: Trace.EmulatorTrace (Trace.ContractHandle () CoinsMachine.BankStateSchema Text)
initialise = do
  Extras.logInfo @Prelude.String "Called initialise"
  oracleHdl <- Trace.activateContractWallet oracleW1 $ Oracle.runMockOracle oracle
  void $ Trace.waitNSlots 10

  Trace.callEndpoint @"update" oracleHdl 1
  void $ Trace.waitNSlots 3

  hdl <- Trace.activateContractWallet w2 $ CoinsMachine.endpoints bp
  
  let i = 5 :: Integer
  Trace.callEndpoint @"start" hdl i
  _ <- Trace.waitNSlots 2
  Extras.logInfo @Prelude.String "Called initialise"
  return hdl

mintStableCoins :: Integer -> Trace.EmulatorTrace ()
mintStableCoins tokenAmount = do
  hdl <- initialise
  Trace.callEndpoint @"mintStableCoin"
    hdl
    CoinsMachine.EndpointInput
      { 
        tokenAmount = tokenAmount
      }
  void $ Trace.waitNSlots 2

-- mintReserveCoins :: Integer -> Integer -> Integer -> Trace.EmulatorTrace ()
-- mintReserveCoins tokenAmount rateNume rateDeno = do
--   hdl <- initialise
--   Trace.callEndpoint @"mintReserveCoin"
--     hdl
--     CoinsMachine.EndpointInput
--       { rateNume = rateNume,
--         rateDeno = rateDeno,
--         tokenAmount = tokenAmount
--       }
--   void $ Trace.waitNSlots 2


-- mintAndRedeemStableCoins :: Integer -> Integer -> Integer -> Integer -> Trace.EmulatorTrace ()
-- mintAndRedeemStableCoins tokenAmountToMint tokenAmountToRedeem rateNume rateDeno = do
--   hdl <- initialise
--   Trace.callEndpoint @"mintStableCoin"
--     hdl
--     CoinsMachine.EndpointInput
--       { rateNume = rateNume,
--         rateDeno = rateDeno,
--         tokenAmount = tokenAmountToMint
--       }
--   void $ Trace.waitNSlots 2  
--   Trace.callEndpoint @"redeemStableCoin"
--       hdl
--       CoinsMachine.EndpointInput
--         { rateNume = rateNume,
--           rateDeno = rateDeno,
--           tokenAmount = tokenAmountToRedeem
--         }
--   void $ Trace.waitNSlots 2

-- mintAndRedeemReserveCoins :: Integer -> Integer -> Integer -> Integer -> Trace.EmulatorTrace ()
-- mintAndRedeemReserveCoins tokenAmountToMint tokenAmountToRedeem rateNume rateDeno = do
--   hdl <- initialise
--   Trace.callEndpoint @"mintReserveCoin"
--     hdl
--     CoinsMachine.EndpointInput
--       { rateNume = rateNume,
--         rateDeno = rateDeno,
--         tokenAmount = tokenAmountToMint
--       }
--   void $ Trace.waitNSlots 2  
--   Trace.callEndpoint @"redeemReserveCoin"
--       hdl
--       CoinsMachine.EndpointInput
--         { rateNume = rateNume,
--           rateDeno = rateDeno,
--           tokenAmount = tokenAmountToRedeem
--         }
--   void $ Trace.waitNSlots 2