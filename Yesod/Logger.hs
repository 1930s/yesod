-- blantantly taken from hakyll
-- http://hackage.haskell.org/packages/archive/hakyll/3.1.1.0/doc/html/src/Hakyll-Core-Logger.html
--
-- | Produce pretty, thread-safe logs
--
{-# LANGUAGE BangPatterns #-}
module Yesod.Logger
    ( Logger
    , makeLogger
    , flushLogger
    , timed
    ) where

import Control.Monad (forever)
import Control.Monad.Trans (MonadIO, liftIO)
import Control.Applicative ((<$>), (<*>))
import Control.Concurrent (forkIO)
import Control.Concurrent.Chan.Strict (Chan, newChan, readChan, writeChan)
import Control.Concurrent.MVar.Strict (MVar, newEmptyMVar, takeMVar, putMVar)
import Text.Printf (printf)

import Data.Time (getCurrentTime, diffUTCTime)

data Logger = Logger
    { loggerChan :: Chan (Maybe String)  -- Nothing marks the end
    , loggerSync :: MVar ()              -- Used for sync on quit
    }

makeLogger :: IO Logger
makeLogger = do
    logger <- Logger <$> newChan <*> newEmptyMVar
    _ <- forkIO $ loggerThread logger
    return logger
  where
    loggerThread logger = forever $ do
        msg <- readChan $ loggerChan logger
        case msg of
            -- Stop: sync
            Nothing -> putMVar (loggerSync logger) ()
            -- Print and continue
            Just m  -> putStrLn m

-- | Flush the logger (blocks until flushed)
--
flushLogger :: Logger -> IO ()
flushLogger logger = do
    writeChan (loggerChan logger) Nothing
    () <- takeMVar $ loggerSync logger
    return ()

-- | Send a raw message to the logger
--
message :: Logger -> String -> IO ()
message logger = writeChan (loggerChan logger) . Just

-- | Execute a monadic action and log the duration
--
timed :: MonadIO m
      => Logger  -- ^ Logger
      -> String  -- ^ Message
      -> m a     -- ^ Action
      -> m a     -- ^ Timed and logged action
timed logger msg action = do
    start <- liftIO getCurrentTime
    !result <- action
    stop <- liftIO getCurrentTime
    let diff = fromEnum $ diffUTCTime stop start
        ms = diff `div` 10 ^ (9 :: Int)
        formatted = printf "  [%4dms] %s" ms msg
    liftIO $ message logger formatted
    return result
