{-# Language OverloadedStrings #-}
module Tests.Lua ( tests ) where

import Control.Monad (when)
import System.FilePath ((</>))
import Test.Tasty (TestTree, localOption)
import Test.Tasty.HUnit (Assertion, assertEqual, testCase)
import Test.Tasty.QuickCheck (ioProperty, testProperty, QuickCheckTests(..))
import Text.Pandoc.Arbitrary ()
import Text.Pandoc.Definition (Block, Inline, Meta, Pandoc)
import Text.Pandoc.Builder ( (<>), bulletList, doc, doubleQuoted, emph
                           , linebreak, rawBlock, singleQuoted, para, plain
                           , space, str, strong)
import Text.Pandoc.Lua

import Foreign.Lua

tests :: [TestTree]
tests = map (localOption (QuickCheckTests 20))
  [ testProperty "inline elements can be round-tripped through the lua stack" $
    \x -> ioProperty (roundtripEqual (x::Inline))

  , testProperty "block elements can be round-tripped through the lua stack" $
    \x -> ioProperty (roundtripEqual (x::Block))

  , testProperty "meta blocks can be round-tripped through the lua stack" $
    \x -> ioProperty (roundtripEqual (x::Meta))

  , testProperty "documents can be round-tripped through the lua stack" $
    \x -> ioProperty (roundtripEqual (x::Pandoc))

  , testCase "macro expansion via filter" $
    assertFilterConversion "a '{{helloworld}}' string is expanded"
      "strmacro.lua"
      (doc . para $ str "{{helloworld}}")
      (doc . para . emph $ str "Hello, World")

  , testCase "convert all plains to paras" $
    assertFilterConversion "plains become para"
      "plain-to-para.lua"
      (doc $ bulletList [plain (str "alfa"), plain (str "bravo")])
      (doc $ bulletList [para (str "alfa"), para (str "bravo")])

  , testCase "make hello world document" $
    assertFilterConversion "Document contains 'Hello, World!'"
      "hello-world-doc.lua"
      (doc . para $ str "Hey!" <> linebreak <> str "What's up?")
      (doc . para $ str "Hello," <> space <> str "World!")

  , testCase "implicit doc filter" $
    assertFilterConversion "Document contains 'Hello, World!'"
      "implicit-doc-filter.lua"
      (doc . plain $ linebreak)
      (doc . para $ str "Hello," <> space <> str "World!")

  , testCase "parse raw markdown blocks" $
    assertFilterConversion "raw markdown block is converted"
      "markdown-reader.lua"
      (doc $ rawBlock "markdown" "*charly* **delta**")
      (doc . para $ emph "charly" <> space <> strong "delta")

  , testCase "allow shorthand functions for quote types" $
    assertFilterConversion "single quoted becomes double quoted string"
      "single-to-double-quoted.lua"
      (doc . para . singleQuoted $ str "simple")
      (doc . para . doubleQuoted $ str "simple")

  , testCase "Count inlines via metatable catch-all" $
    assertFilterConversion "filtering with metatable catch-all failed"
      "metatable-catch-all.lua"
      (doc . para $ "four words, three spaces")
      (doc . para $ str "7")

  , testCase "Count blocks via Block-specific catch-all" $
    assertFilterConversion "filtering with Block catch-all failed"
      "block-count.lua"
      (doc $ para "one" <> para "two")
      (doc $ para "2")
  ]

assertFilterConversion :: String -> FilePath -> Pandoc -> Pandoc -> Assertion
assertFilterConversion msg filterPath docIn docExpected = do
  docRes <- runLuaFilter (Just "../data") ("lua" </> filterPath) [] docIn
  assertEqual msg docExpected docRes

roundtripEqual :: (Eq a, FromLuaStack a, ToLuaStack a) => a -> IO Bool
roundtripEqual x = (x ==) <$> roundtripped
 where
  roundtripped :: (FromLuaStack a, ToLuaStack a) => IO a
  roundtripped = runLua $ do
    openlibs
    pushPandocModule (Just "../data")
    setglobal "pandoc"
    oldSize <- gettop
    push x
    size <- gettop
    when ((size - oldSize) /= 1) $
      error ("not exactly one additional element on the stack: " ++ show size)
    res <- peekEither (-1)
    case res of
      Left _ -> error "could not read from stack"
      Right y  -> return y
