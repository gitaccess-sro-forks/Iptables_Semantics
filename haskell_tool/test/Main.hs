module Main where

import Test.Tasty

import qualified Suites.ParserHelper
import qualified Suites.Parser
import qualified Suites.FffuuBinary

main :: IO ()
main = defaultMain $ testGroup "fffuu"
  [ Suites.ParserHelper.tests
  , Suites.Parser.tests
  , Suites.FffuuBinary.tests
  ]
