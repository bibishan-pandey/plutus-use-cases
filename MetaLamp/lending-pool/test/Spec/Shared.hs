{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Spec.Shared where

import qualified Fixtures
import           Plutus.Contract.Test    (TracePredicate)
import qualified Plutus.Contracts.Core   as Aave
import           Plutus.V1.Ledger.Crypto (PubKeyHash)
import           Plutus.V1.Ledger.Value  (AssetClass)
import qualified PlutusTx.AssocMap       as AssocMap
import qualified Utils.Data              as Utils
import qualified Utils.Trace             as Utils

reservesChange :: AssocMap.Map AssetClass Aave.Reserve -> TracePredicate
reservesChange reserves = Utils.datumsAtAddress Fixtures.aaveAddress (Utils.one check)
    where
        check (Aave.ReservesDatum _ reserves') = reserves' == reserves
        check _                                = False

userConfigsChange :: AssocMap.Map (AssetClass, PubKeyHash) Aave.UserConfig -> TracePredicate
userConfigsChange configs = Utils.datumsAtAddress Fixtures.aaveAddress (Utils.one check)
    where
        check (Aave.UserConfigsDatum _ configs') = configs' == configs
        check _                                  = False
