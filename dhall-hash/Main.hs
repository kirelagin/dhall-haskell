{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RecordWildCards    #-}
{-# LANGUAGE TypeOperators      #-}

module Main where

import Control.Exception (SomeException)
import Control.Monad (when)
import Data.Version (showVersion)
import Dhall.Core (normalize)
import Dhall.Import (Imported(..), hashExpressionToCode, load)
import Dhall.Parser (Src, exprFromText)
import Dhall.TypeCheck (DetailedTypeError(..), TypeError, X)
import Options.Generic (Generic, ParseRecord, Wrapped, type (<?>)(..), (:::))
import System.IO (stderr)
import System.Exit (exitFailure, exitSuccess)

import qualified Paths_dhall as Meta

import qualified Control.Exception
import qualified Data.Text.Lazy.IO
import qualified Dhall.TypeCheck
import qualified Options.Generic
import qualified System.IO

data Options w = Options
    { explain :: w ::: Bool <?> "Explain error messages in more detail"
    , version :: w ::: Bool <?> "Display version and exit"
    } deriving (Generic)

instance ParseRecord (Options Wrapped)

main :: IO ()
main = do
    Options {..} <- Options.Generic.unwrapRecord "Compiler for the Dhall language"
    when version $ do
      putStrLn (showVersion Meta.version)
      exitSuccess
    let handle =
                Control.Exception.handle handler2
            .   Control.Exception.handle handler1
            .   Control.Exception.handle handler0
          where
            handler0 e = do
                let _ = e :: TypeError Src X
                System.IO.hPutStrLn stderr ""
                if explain
                    then Control.Exception.throwIO (DetailedTypeError e)
                    else do
                        Data.Text.Lazy.IO.hPutStrLn stderr "\ESC[2mUse \"dhall --explain\" for detailed errors\ESC[0m"
                        Control.Exception.throwIO e

            handler1 (Imported ps e) = do
                let _ = e :: TypeError Src X
                System.IO.hPutStrLn stderr ""
                if explain
                    then Control.Exception.throwIO (Imported ps (DetailedTypeError e))
                    else do
                        Data.Text.Lazy.IO.hPutStrLn stderr "\ESC[2mUse \"dhall --explain\" for detailed errors\ESC[0m"
                        Control.Exception.throwIO (Imported ps e)

            handler2 e = do
                let _ = e :: SomeException
                System.IO.hSetEncoding System.IO.stderr System.IO.utf8
                System.IO.hPrint stderr e
                System.Exit.exitFailure

    handle (do
        System.IO.hSetEncoding System.IO.stdin System.IO.utf8
        inText <- Data.Text.Lazy.IO.getContents

        expr <- case exprFromText "(stdin)" inText of
            Left  err  -> Control.Exception.throwIO err
            Right expr -> return expr

        expr' <- load expr

        _ <- case Dhall.TypeCheck.typeOf expr' of
            Left  err -> Control.Exception.throwIO err
            Right _   -> return ()

        Data.Text.Lazy.IO.putStrLn (hashExpressionToCode (normalize expr')) )
