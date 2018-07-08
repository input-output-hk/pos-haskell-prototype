{-# LANGUAGE DataKinds #-}

module Pos.Ssc.Mode
       ( SscMode
       ) where

import           Universum

import qualified Crypto.Random as Rand
import           Mockable (MonadMockable)
import           System.Wlog (WithLogger)

import           Pos.Core (HasPrimaryKey)
import           Pos.DB.Class (MonadDB, MonadGState)
import           Pos.Lrc.Context (HasLrcContext)
import           Pos.Security.Params (SecurityParams)
import           Pos.Sinbin.Recovery.Info (MonadRecoveryInfo)
import           Pos.Sinbin.Reporting (MonadReporting)
import           Pos.Sinbin.Shutdown (HasShutdownContext)
import           Pos.Sinbin.Slotting (MonadSlots)
import           Pos.Sinbin.Util.TimeWarp (CanJsonLog)
import           Pos.Ssc.Configuration (HasSscConfiguration)
import           Pos.Ssc.Mem (MonadSscMem)
import           Pos.Ssc.Types (HasSscContext)
import           Pos.Util.Util (HasLens (..))

-- | Mode used for all SSC listeners, workers, and the like.
type SscMode ctx m
    = ( WithLogger m
      , CanJsonLog m
      , MonadIO m
      , Rand.MonadRandom m
      , MonadMask m
      , MonadMockable m
      , MonadSlots ctx m
      , MonadGState m
      , MonadDB m
      , MonadSscMem ctx m
      , MonadRecoveryInfo m
      , HasShutdownContext ctx
      , MonadReader ctx m
      , HasSscContext ctx
      , MonadReporting m
      , HasPrimaryKey ctx
      , HasLens SecurityParams ctx SecurityParams
      , HasLrcContext ctx
      , HasSscConfiguration
      )
