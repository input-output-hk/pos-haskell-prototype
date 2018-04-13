{-# LANGUAGE RankNTypes    #-}
{-# LANGUAGE TupleSections #-}

module Main where

import           Universum

import           Cardano.Wallet.Client.Http
import           Control.Lens hiding ((^..), (^?))
import           Data.Map (fromList)
import           Data.Traversable (for)
import           System.IO (hSetEncoding, stdout, utf8)
import           Test.Hspec
import           Test.QuickCheck (arbitrary, generate)

import           CLI
import           Functions
import           Types

-- | Here we want to run main when the (local) nodes
-- have started.
main :: IO ()
main = do

    hSetEncoding stdout utf8
    CLOptions {..} <- getOptions

    _pubCert <- readFile tlsPubCertPath
    _privKey <- readFile tlsPrivKeyPath
    -- stateless

    -- TODO (akegalj): run server cluster in haskell, instead of using shell scripts
    -- serverThread <- async (runWalletServer options)

    printT "Starting the integration testing for wallet."

    when stateless $ do
        printT "The wallet test node is running in stateless mode."
        printT "Stateless mode not implemented currently!"

    -- TODO (akegalj): move these to CLOptions
    let baseUrl = BaseUrl Http "localhost" 8090 mempty
    manager <- newManager defaultManagerSettings

    let walletClient :: MonadIO m => WalletClient m
        walletClient = liftClient $ mkHttpClient baseUrl manager

    walletState <- initialWalletState walletClient

    printT $ "Initial wallet state: " <> show walletState

    -- some monadic fold or smth similar
    _ <- runActionCheck
        walletClient
        walletState
        actionDistribution

    hspec $ deterministicTests walletClient
  where
    actionDistribution :: ActionProbabilities
    actionDistribution = do
        (PostWallet, Weight 2) :| fmap (\x -> (x, Weight 1)) [minBound .. maxBound]

initialWalletState :: WalletClient IO -> IO WalletState
initialWalletState wc = do
    -- We will have single genesis wallet in intial state that was imported from launching script
    _wallets <- fromResp $ getWallets wc
    _accounts <- concat <$> for _wallets (fromResp . getAccounts wc . walId)
    -- Lets set all wallet passwords for initial wallets (genesis) to default (emptyPassphrase)
    let _walletsPass  = fromList $ map ((, V1 mempty) . walId) _wallets
        _addresses    = concatMap accAddresses _accounts
        -- TODO(akegalj): I am not sure does importing a genesis wallet (which we do prior launching integration tests) creates a transaction
        -- If it does, we should add this transaction to the list
        _transactions = mempty
        _actionsNum   = 0
        _successNum   = 0
    pure $ WalletState {..}
  where
    fromResp = (either throwM (pure . wrData) =<<)

deterministicTests :: WalletClient IO -> Spec
deterministicTests wc = do
    describe "Addresses" $ do
        it "Creating an address makes it available" $ do
            -- create a wallet
            newWallet <- randomWallet
            Wallet{..} <- createWalletCheck newWallet

            -- create an account
            accResp <- postAccount wc walId (NewAccount Nothing "hello")
            acc@Account{..} <- wrData <$> accResp `shouldPrism` _Right

            -- accounts should exist
            accResp' <- getAccounts wc walId
            accs <- wrData <$> accResp' `shouldPrism` _Right
            accs `shouldContain` [acc]

            -- create an address
            addResp <- postAddress wc (NewAddress Nothing accIndex walId)
            addr <- wrData <$> addResp `shouldPrism` _Right

            -- verify that address is in the API
            idxResp <- getAddressIndex wc
            addrs <- wrData <$> idxResp `shouldPrism` _Right

            map addrId addrs `shouldContain` [addrId addr]

        it "Index returns real data" $ do
            addrsResp <- getAddressIndex wc
            addrs <- wrData <$> addrsResp `shouldPrism` _Right

            addrsResp' <- getAddressIndex wc
            addrs' <- wrData <$> addrsResp' `shouldPrism` _Right

            addrs `shouldBe` addrs'

    describe "Wallets" $ do
        it "Creating a wallet makes it available." $ do
            newWallet <- randomWallet
            Wallet{..} <- createWalletCheck newWallet

            eresp <- getWallet wc walId
            void $ eresp `shouldPrism` _Right
        it "Updating a wallet persists the update" $ do
            newWallet <- randomWallet
            wallet <- createWalletCheck newWallet
            let newName = "Foobar Bazquux"
                newAssurance = NormalAssurance
            eupdatedWallet <- updateWallet wc (walId wallet) WalletUpdate
                { uwalName = newName
                , uwalAssuranceLevel = newAssurance
                }
            Wallet{..} <- wrData <$> eupdatedWallet `shouldPrism` _Right
            walName `shouldBe` newName
            walAssuranceLevel `shouldBe` newAssurance

  where
    randomWallet =
        generate $
            NewWallet
                <$> arbitrary
                <*> pure Nothing
                <*> arbitrary
                <*> pure "Wallet"
                <*> pure CreateWallet
    createWalletCheck newWallet = do
        result <- fmap wrData <$> postWallet wc newWallet
        result `shouldPrism` _Right


shouldPrism :: Show s => s -> Prism' s a -> IO a
shouldPrism a b = do
    a `shouldSatisfy` has b
    let Just x = a ^? b
    pure x

infixr 8 `shouldPrism`
