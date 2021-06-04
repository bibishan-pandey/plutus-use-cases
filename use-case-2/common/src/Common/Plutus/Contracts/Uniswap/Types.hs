{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Common.Plutus.Contracts.Uniswap.Types where

import Data.Aeson
import Data.Text (Text)
import GHC.Generics

newtype Coin a = Coin { unCoin :: AssetClass }
  deriving newtype (Generic, Show, ToJSON, FromJSON)

newtype AssetClass = AssetClass { unAssetClass :: (CurrencySymbol, TokenName) }
  deriving (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

newtype CurrencySymbol = CurrencySymbol { unCurrencySymbol :: Text }
  deriving (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

newtype TokenName = TokenName { unTokenName :: Text }
  deriving (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

newtype Amount  a = Amount { unAmount :: Integer }
  deriving (Generic, Show)
  deriving newtype (ToJSON, FromJSON)

newtype ContractInstanceId a = ContractInstanceId { unContractInstanceId :: Text }
  deriving (Generic, Show)
  deriving newtype (ToJSON, FromJSON)

data SwapParams = SwapParams
    { spCoinA   :: Coin AssetClass      -- ^ One 'Coin' of the liquidity pair.
    , spCoinB   :: Coin AssetClass      -- ^ The other 'Coin'.
    , spAmountA :: Amount Integer     -- ^ The amount the first 'Coin' that should be swapped.
    , spAmountB :: Amount Integer    -- ^ The amount of the second 'Coin' that should be swapped.
    } deriving (Generic, Show)

instance ToJSON SwapParams
instance FromJSON SwapParams
