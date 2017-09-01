-- | Functions operation on 'SlogContext' and its subtypes.

module Pos.Block.Slog.Context
       ( SlogGState (..)
       , SlogContext (..)

       , mkSlogGState
       , mkSlogContext
       , cloneSlogGState
       , slogGetLastSlots
       , slogPutLastSlots
       ) where

import           Universum

import           Formatting            (int, sformat, (%))
import qualified System.Metrics        as Ekg

import           Pos.Block.Slog.Types  (HasSlogGState (..), LastBlkSlots,
                                        SlogContext (..), SlogGState (..),
                                        sgsLastBlkSlots)
import           Pos.Core              (HasCoreConstants, blkSecurityParam,
                                        fixedTimeCQSec)
import           Pos.DB.Class          (MonadDBRead)
import           Pos.GState.BlockExtra (getLastSlots)
import           Pos.Reporting         (mkMetricMonitorState)

-- | Make new 'SlogGState' using data from DB.
mkSlogGState :: (MonadIO m, MonadDBRead m) => m SlogGState
mkSlogGState = do
    _sgsLastBlkSlots <- getLastSlots >>= newIORef
    return SlogGState {..}

-- | Make new 'SlogContext' using data from DB.
mkSlogContext ::
       (MonadIO m, MonadDBRead m, HasCoreConstants)
    => Maybe Ekg.Store
    -> m SlogContext
mkSlogContext storeMaybe = do
    _scGState <- mkSlogGState

    let mkMMonitorState = flip mkMetricMonitorState storeMaybe
    -- Chain quality metrics stuff.
    let metricNameK =
            sformat ("chain_quality_last_k_("%int%")_blocks_milli")
                blkSecurityParam
    let metricNameOverall = "chain_quality_overall_milli"
    let metricNameFixed =
            sformat ("chain_quality_last_"%int%"_sec_milli")
                fixedTimeCQSec
    _scCQkMonitorState <- mkMMonitorState metricNameK
    _scCQOverallMonitorState <- mkMMonitorState metricNameOverall
    _scCQFixedMonitorState <- mkMMonitorState metricNameFixed

    -- Other metrics stuff.
    _scDifficultyMonitorState <- mkMMonitorState "total_main_blocks"
    return SlogContext {..}

-- | Make a copy of existing 'SlogGState'.
cloneSlogGState :: (MonadIO m) => SlogGState -> m SlogGState
cloneSlogGState SlogGState {..} =
    SlogGState <$> (readIORef _sgsLastBlkSlots >>= newIORef)

-- | Read 'LastBlkSlots' from in-memory state.
slogGetLastSlots ::
       (MonadReader ctx m, HasSlogGState ctx, MonadIO m) => m LastBlkSlots
slogGetLastSlots = view (slogGState . sgsLastBlkSlots) >>= readIORef

-- | Update 'LastBlkSlots' in 'SlogContext'.
slogPutLastSlots ::
       (MonadReader ctx m, HasSlogGState ctx, MonadIO m)
    => LastBlkSlots
    -> m ()
slogPutLastSlots slots =
    view (slogGState . sgsLastBlkSlots) >>= flip writeIORef slots
