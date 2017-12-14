{-- | IxSet-specific backend to filter data from the model. --}
module Cardano.Wallet.API.Response.Filter.IxSet (
      applyFilters
      ) where

import           Universum

import           Cardano.Wallet.API.Indices (Indexable', IsIndexOf', IxSet')
import qualified Cardano.Wallet.API.Request.Filter as F
import           Data.IxSet.Typed ((@<), (@=), (@>), (@>=<=))

-- | Applies all the input filters to the input 'IxSet''.
applyFilters :: Indexable' a => F.FilterOperations a -> IxSet' a -> IxSet' a
applyFilters F.NoFilters iset        = iset
applyFilters (F.FilterOp f fop) iset = applyFilters fop (applyFilter f iset)

-- | Applies a single 'FilterOperation' on the input 'IxSet'', producing another 'IxSet'' as output.
applyFilter :: forall ix a. (Indexable' a , IsIndexOf' a ix) => F.FilterOperation ix a -> IxSet' a -> IxSet' a
applyFilter fltr inputData =
    let byPredicate o i = case o of
            EQ -> inputData @= (i :: ix)
            LT -> inputData @< (i :: ix)
            GT -> inputData @> (i :: ix)
    in case fltr of
           F.FilterIdentity             -> inputData
           F.FilterByIndex idx          -> byPredicate EQ idx
           F.FilterByPredicate ordr idx -> byPredicate ordr idx
           F.FilterByRange from to      -> inputData @>=<= (from, to)
