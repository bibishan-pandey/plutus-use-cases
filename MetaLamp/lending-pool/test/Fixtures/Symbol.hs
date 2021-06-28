{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MonoLocalBinds   #-}
{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE TypeApplications #-}

module Fixtures.Symbol where

import           Control.Monad             (void)
import           Data.Text                 (Text)
import           Data.Void                 (Void)
import qualified Ledger
import qualified Ledger.Constraints        as Constraints
import           Ledger.Typed.Scripts      (MonetaryPolicy)
import qualified Ledger.Typed.Scripts      as Scripts
import           Plutus.Contract
import qualified Plutus.Contracts.TxUtils  as TxUtils
import           Plutus.V1.Ledger.Contexts (ScriptContext)
import qualified Plutus.V1.Ledger.Scripts  as Scripts
import           Plutus.V1.Ledger.Value    (CurrencySymbol, TokenName,
                                            assetClass, assetClassValue)
import qualified PlutusTx

{-# INLINABLE validator #-}
validator :: TokenName -> ScriptContext -> Bool
validator _ _ = True

makePolicy :: TokenName -> MonetaryPolicy
makePolicy tokenName = Scripts.mkMonetaryPolicyScript $
  $$(PlutusTx.compile [|| Scripts.wrapMonetaryPolicy . validator ||])
    `PlutusTx.applyCode`
        PlutusTx.liftCode tokenName

getSymbol :: TokenName -> CurrencySymbol
getSymbol = Ledger.scriptCurrencySymbol . makePolicy

forgeSymbol :: HasBlockchainActions s => TokenName -> Contract () s Text CurrencySymbol
forgeSymbol tokenName = do
    pkh <- Ledger.pubKeyHash <$> ownPubKey
    let symbol = getSymbol tokenName
        forgeValue = assetClassValue (assetClass symbol tokenName) 1
    ledgerTx <-
        TxUtils.submitTxPair $
            TxUtils.mustForgeValue @Void (makePolicy tokenName) forgeValue
            <> (mempty, Constraints.mustPayToPubKey pkh forgeValue)
    void $ awaitTxConfirmed $ Ledger.txId ledgerTx
    pure symbol
