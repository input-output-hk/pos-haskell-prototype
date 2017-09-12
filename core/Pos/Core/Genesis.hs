module Pos.Core.Genesis
       (
       -- * Constants/devmode
         genesisDevKeyPairs
       , genesisDevPublicKeys
       , genesisDevSecretKeys
       , genesisDevHdwSecretKeys
       , genesisDevFlatDistr

       -- * /genesis-core.bin/
       , module Pos.Core.Genesis.Types
       , compileGenSpec

       -- ** Derived data
       , genesisProdAvvmDistr
       , genesisProdInitializer
       , genesisProdDelegation

       -- * Utils
       , generateGenesisKeyPair
       , generateHdwGenesisSecretKey
       ) where

import           Universum

import qualified Data.Text               as T
import           Formatting              (int, sformat, (%))

import           Pos.Binary.Crypto       ()
import           Pos.Core.Coin           (unsafeMulCoin)
import           Pos.Core.Constants      (genesisKeysN)
import           Pos.Core.Genesis.Parser (compileGenSpec)
import           Pos.Core.Genesis.Types  (AddrDistribution (..), BalanceDistribution (..),
                                          FakeAvvmOptions (..), GenesisAddrDistr (..),
                                          GenesisData (..), GenesisDelegation (..),
                                          GenesisInitializer (..), GenesisSpec (..),
                                          GenesisSpec (..), GenesisWStakeholders (..),
                                          TestBalanceOptions (..),
                                          TestnetDistribution (..), bootDustThreshold,
                                          getTotalBalance, mkGenesisDelegation,
                                          mkGenesisSpec, noGenesisDelegation,
                                          safeExpBalances)
import           Pos.Core.Types          (Address, mkCoin)
import           Pos.Crypto.SafeSigning  (EncryptedSecretKey, emptyPassphrase,
                                          safeDeterministicKeyGen)
import           Pos.Crypto.Signing      (PublicKey, SecretKey, deterministicKeyGen)

----------------------------------------------------------------------------
-- Constants/development
----------------------------------------------------------------------------

-- | List of pairs from 'SecretKey' with corresponding 'PublicKey'.
genesisDevKeyPairs :: [(PublicKey, SecretKey)]
genesisDevKeyPairs = map generateGenesisKeyPair [0 .. genesisKeysN - 1]

-- | List of 'PublicKey's in genesis.
genesisDevPublicKeys :: [PublicKey]
genesisDevPublicKeys = map fst genesisDevKeyPairs

-- | List of 'SecretKey's in genesis.
genesisDevSecretKeys :: [SecretKey]
genesisDevSecretKeys = map snd genesisDevKeyPairs

-- | List of 'SecretKey's in genesis for HD wallets.
genesisDevHdwSecretKeys :: [EncryptedSecretKey]
genesisDevHdwSecretKeys =
    map generateHdwGenesisSecretKey [0 .. genesisKeysN - 1]

-- | Default flat stakes distributed among 'genesisKeysN' (from constants).
genesisDevFlatDistr :: BalanceDistribution
genesisDevFlatDistr =
    FlatBalances genesisKeysN $
    mkCoin 10000 `unsafeMulCoin` (genesisKeysN :: Int)

----------------------------------------------------------------------------
-- GenesisCore derived data, production
----------------------------------------------------------------------------

-- | Avvm distribution
genesisProdAvvmDistr :: GenesisAddrDistr
genesisProdAvvmDistr = gsAvvmDistr compileGenSpec

-- | Genesis initializer determines way of initialization
-- utxo, bootstrap stakeholders and etc.
genesisProdInitializer :: GenesisInitializer
genesisProdInitializer = gsInitializer compileGenSpec

-- | 'GenesisDelegation' for production mode.
genesisProdDelegation :: GenesisDelegation
genesisProdDelegation = gsHeavyDelegation compileGenSpec

----------------------------------------------------------------------------
-- Utils
----------------------------------------------------------------------------

generateGenesisKeyPair :: Int -> (PublicKey, SecretKey)
generateGenesisKeyPair =
    deterministicKeyGen .
    encodeUtf8 .
    T.take 32 . sformat ("My awesome 32-byte seed #" %int % "             ")

generateHdwGenesisSecretKey :: Int -> EncryptedSecretKey
generateHdwGenesisSecretKey =
    snd .
    flip safeDeterministicKeyGen emptyPassphrase .
    encodeUtf8 .
    T.take 32 . sformat ("My 32-byte hdw seed #" %int % "                  ")
