module Cardano.Wallet.API.V1.LegacyHandlers.Transactions where

import           Universum

import qualified Data.IxSet.Typed as IxSet
import qualified Data.List.NonEmpty as NE

import           Pos.Client.Txp.Util (defaultInputSelectionPolicy)
import qualified Pos.Client.Txp.Util as V0
import           Pos.Core (TxAux)
import qualified Pos.Core as Core
import qualified Pos.Util.Servant as V0
import qualified Pos.Wallet.WalletMode as V0
import qualified Pos.Wallet.Web.ClientTypes.Types as V0
import qualified Pos.Wallet.Web.Methods.History as V0
import qualified Pos.Wallet.Web.Methods.Logic as V0
import qualified Pos.Wallet.Web.Methods.Payment as V0
import qualified Pos.Wallet.Web.Methods.Txp as V0
import qualified Pos.Wallet.Web.State as V0
import           Pos.Wallet.Web.State.Storage (WalletInfo (_wiSyncStatistics))
import qualified Pos.Wallet.Web.Util as V0
import qualified Pos.Txp as Txp

import           Cardano.Wallet.API.Request
import           Cardano.Wallet.API.Response
import           Cardano.Wallet.API.V1.Errors
import           Cardano.Wallet.API.V1.Migration (HasCompileInfo, HasConfigurations, MonadV1,
                                                  migrate)
import qualified Cardano.Wallet.API.V1.Transactions as Transactions
import           Cardano.Wallet.API.V1.Types

import           Servant

handlers
    :: (HasConfigurations, HasCompileInfo)
    => (TxAux -> MonadV1 Bool)
    -> ServerT Transactions.API MonadV1
handlers submitTx =
         newTransaction submitTx
    :<|> allTransactions
    :<|> estimateFees

newTransaction
    :: forall ctx m. (V0.MonadWalletTxFull ctx m)
    => (TxAux -> m Bool)
    -> Payment
    -> m (WalletResponse Transaction)
newTransaction submitTx Payment {..} = do
    ws <- V0.askWalletSnapshot
    sourceWallet <- migrate (psWalletId pmtSource)

    -- If the wallet is being restored, we need to disallow any @Payment@ from
    -- being submitted.
    -- FIXME(adn): make grabbing a 'V1.SyncState' from the old data layer
    -- easier and less verbose.
    when (V0.isWalletRestoring ws sourceWallet) $ do
        let stats    = _wiSyncStatistics <$> V0.getWalletInfo ws sourceWallet
        currentHeight <- V0.networkChainDifficulty
        progress <- case liftM2 (,) stats currentHeight  of
                        Nothing     -> pure $ SyncProgress (mkEstimatedCompletionTime 0)
                                                           (mkSyncThroughput (Core.BlockCount 0))
                                                           (mkSyncPercentage 0)
                        Just (s, h) -> migrate (s, Just h)
        throwM $ WalletIsNotReadyToProcessPayments progress

    let (V1 spendingPw) = fromMaybe (V1 mempty) pmtSpendingPassword
    cAccountId <- migrate pmtSource
    addrCoinList <- migrate $ NE.toList pmtDestinations
    let (V1 policy) = fromMaybe (V1 defaultInputSelectionPolicy) pmtGroupingPolicy
    let batchPayment = V0.NewBatchPayment cAccountId addrCoinList policy
    cTx <- V0.newPaymentBatch submitTx spendingPw batchPayment
    single <$> migrate cTx


allTransactions
    :: forall ctx m. (V0.MonadWalletHistory ctx m)
    => Maybe WalletId
    -> Maybe AccountIndex
    -> Maybe (V1 Core.Address)
    -> RequestParams
    -> FilterOperations Transaction
    -> SortOperations Transaction
    -> m (WalletResponse [Transaction])
allTransactions mwalletId mAccIdx mAddr requestParams fops sops  =
    case mwalletId of
        Just walletId -> do
            cIdWallet <- migrate walletId
            ws <- V0.askWalletSnapshot

            -- Create a `[V0.AccountId]` to get txs from it
            let accIds = case mAccIdx of
                    Just accIdx -> migrate (walletId, accIdx)
                    -- ^ Migrate `V1.AccountId` into `V0.AccountId` and put it into a list
                    Nothing     -> V0.getWalletAccountIds ws cIdWallet
                    -- ^ Or get all `V0.AccountId`s of a wallet

            let v0Addr = case mAddr of
                    Nothing        -> Nothing
                    Just (V1 addr) -> Just $ V0.encodeCType addr

            -- get all `[Transaction]`'s
            let transactions = do
                    (V0.WalletHistory wh, _) <- V0.getHistory cIdWallet (const accIds) v0Addr
                    migrate wh

            -- Paginate result
            respondWith requestParams fops sops (IxSet.fromList <$> transactions)
        _ ->
            -- TODO: should we use the 'FilterBy' machinery instead? that
            --       let us express RANGE, GT, etc. in addition to EQ. does
            --       that make sense for this dataset?
            throwM MissingRequiredParams
                { requiredParams = pure ("wallet_id", "WalletId")
                }

estimateFees :: (MonadThrow m, V0.MonadFees ctx m, V0.MonadWalletLogicRead ctx m)
    => Payment
    -> m (WalletResponse EstimatedFees)
estimateFees Payment{..} = do
    ws <- V0.askWalletSnapshot
    let (V1 policy) = fromMaybe (V1 defaultInputSelectionPolicy) pmtGroupingPolicy
        pendingAddrs = V0.getPendingAddresses ws policy
    cAccountId <- migrate pmtSource
    utxo <- V0.getMoneySourceUtxo ws (V0.AccountMoneySource cAccountId)
    outputs <- V0.coinDistrToOutputs =<< mapM migrate pmtDestinations
    efee <- V0.runTxCreator policy (V0.computeTxFee pendingAddrs utxo outputs)
    single <$> case efee of
        Left txError ->
            let
                estimatedFee coin =
                    pure (mkLowerBoundFee pmtDestinations utxo coin)
            in
                case txError of
                    V0.NotEnoughMoney coin ->
                        estimatedFee coin
                    V0.NotEnoughAllowedMoney coin ->
                        estimatedFee coin
                    _ ->
                        throwM (transactionErrorToWalletError txError)
        Right fee ->
            migrate (fee, Accurate)

-- | Create a lower bound estimate, given the account's available cash and
-- the amount of additional coins necesssary to complete the transaction.
-- This function is a safe wrapper around 'mkLowerBound' that derives the
-- required amounts from the given values.
mkLowerBoundFee
    :: NonEmpty PaymentDistribution
    -- ^ The payment distributions that were attempted.
    -> Txp.Utxo
    -- ^ The account's Utxo.
    -> Core.Coin
    -- ^ The amount of coins necessary to complete the transaction.
    -> EstimatedFees
mkLowerBoundFee payments utxo amountUnder =
    EstimatedFees
        (V1 (Core.mkCoin (fromIntegral estimatedFeeAmount)))
        LowerBound
  where
    utxoAmount =
        sum (fmap (Core.getCoin . Txp.txOutValue . Txp.toaOut) utxo)
    estimatedFeeAmount =
        rawMkLowerBound
            (TxnAmount txnAmount)
            (AvailableCoin utxoAmount)
            (AdditionalCoin (Core.getCoin amountUnder))
    txnAmount =
        sum (fmap (Core.getCoin . unV1 . pdAmount) payments)

newtype TxnAmount = TxnAmount Word64
newtype AvailableCoin = AvailableCoin Word64
newtype AdditionalCoin = AdditionalCoin Word64

-- | TODO: write a real doc comment
rawMkLowerBound
    :: TxnAmount
    -- ^ The transaction total amount.
    -> AvailableCoin
    -- ^ The account's available cash, acquired from the Utxo.
    -> AdditionalCoin
    -- ^ The amount of coins necessary to complete the transaction.
    -> Word64
rawMkLowerBound
    (TxnAmount txnTotal)
    (AvailableCoin acctAmount)
    (AdditionalCoin amountUnder)
  =
    feeLowerBound
  where
    feeLowerBound =
        totalToSpend - txnTotal
    totalToSpend =
        amountUnder + acctAmount
