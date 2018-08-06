-- | Getter params from Args

module Pos.Client.CLI.Params
       ( loggingParams
       , getBaseParams
       , getKeyfilePath
       , getNodeParams
       , gtSscParams
       ) where

import           Universum

import           Data.Default (def)
import qualified Data.Yaml as Yaml

import           Pos.Behavior (BehaviorConfig (..))
import           Pos.Chain.Ssc (SscParams (..))
import           Pos.Chain.Update (UpdateParams (..))
import           Pos.Client.CLI.NodeOptions (CommonNodeArgs (..), NodeArgs (..))
import           Pos.Client.CLI.Options (CommonArgs (..))
import           Pos.Client.CLI.Secrets (prepareUserSecret)
import           Pos.Core.Configuration (HasConfiguration)
import           Pos.Crypto (VssKeyPair)
import           Pos.Infra.Network.CLI (intNetworkConfigOpts)
import           Pos.Launcher.Param (BaseParams (..), LoggingParams (..),
                     NodeParams (..))
import           Pos.Util.Log (LoggerName)
import           Pos.Util.Trace (noTrace)
import           Pos.Util.UserSecret (peekUserSecret)
import           Pos.Util.Util (eitherToThrow)

loggingParams :: LoggerName -> CommonNodeArgs -> LoggingParams
loggingParams defaultName CommonNodeArgs{..} =
    LoggingParams
    { lpHandlerPrefix = logPrefix commonArgs
    , lpConfigPath    = logConfig commonArgs
    , lpDefaultName   = defaultName
    , lpConsoleLog    = Nothing -- no override by default
    }

getBaseParams :: LoggerName -> CommonNodeArgs -> BaseParams
getBaseParams defaultLoggerName args@CommonNodeArgs {..} =
    BaseParams { bpLoggingParams = loggingParams defaultLoggerName args }

gtSscParams :: CommonNodeArgs -> VssKeyPair -> BehaviorConfig -> SscParams
gtSscParams CommonNodeArgs {..} vssSK BehaviorConfig{..} =
    SscParams
    { spSscEnabled = True
    , spVssKeyPair = vssSK
    , spBehavior   = bcSscBehavior
    }

getKeyfilePath :: CommonNodeArgs -> FilePath
getKeyfilePath CommonNodeArgs {..}
    = case devGenesisSecretI of
          Nothing -> keyfilePath
          Just i  -> "node-" ++ show i ++ "." ++ keyfilePath

getNodeParams ::
       ( MonadIO m
       , MonadCatch m
       , HasConfiguration
       )
    => LoggerName
    -> CommonNodeArgs
    -> NodeArgs
    -> m NodeParams
getNodeParams defaultLoggerName cArgs@CommonNodeArgs{..} NodeArgs{..} = do
    (primarySK, userSecret) <-
        prepareUserSecret noTrace cArgs =<< peekUserSecret noTrace (getKeyfilePath cArgs)
    npNetworkConfig <- intNetworkConfigOpts noTrace networkConfigOpts
    npBehaviorConfig <- case behaviorConfigPath of
        Nothing -> pure def
        Just fp -> eitherToThrow =<< liftIO (Yaml.decodeFileEither fp)
    pure NodeParams
        { npDbPathM = dbPath
        , npRebuildDb = rebuildDB
        , npSecretKey = primarySK
        , npUserSecret = userSecret
        , npBaseParams = getBaseParams defaultLoggerName cArgs
        , npJLFile = jlPath
        , npReportServers = reportServers commonArgs
        , npUpdateParams = UpdateParams
            { upUpdatePath    = updateLatestPath
            , upUpdateWithPkg = updateWithPackage
            , upUpdateServers = updateServers commonArgs
            }
        , npRoute53Params = route53Params
        , npEnableMetrics = enableMetrics
        , npEkgParams = ekgParams
        , npStatsdParams = statsdParams
        , npAssetLockPath = cnaAssetLockPath
        , ..
        }
