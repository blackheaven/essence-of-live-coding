{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE RecordWildCards #-}
module Handle where

-- base
import Control.Arrow
import Data.Functor
import Data.Functor.Identity

-- transformers
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.State.Strict

-- test-framework
import Test.Framework

-- test-framework-quickcheck2
import Test.Framework.Providers.QuickCheck2

-- essence-of-live-coding
import qualified Handle.LiveProgram
import LiveCoding
import Util

testHandle :: Handle (State Int) String
testHandle = Handle
  { create = do
      n <- get
      return $ "Handle #" ++ show n
  , destroy = const $ put 10000
  }

testUnitHandle :: Handle (State Int) ()
testUnitHandle = Handle
  { create = return ()
  , destroy = const $ put 20000
  }

cellWithAction
  :: forall a b . State Int b
  -> Cell Identity a (String, Int)
cellWithAction action = flip runStateC 0 $ runHandlingStateC $ handling testHandle >>> arrM (<$ lift action)

testParametrisedHandle :: ParametrisedHandle Bool (State Int) String
testParametrisedHandle = ParametrisedHandle { .. }
  where
    createParametrised flag = do
      n <- get
      let greeting = if flag then "Ye Olde Handle No " else "Crazy new hdl #"
      return $ greeting ++ show n
    destroyParametrised = const $ const $ put 12345
    changeParametrised = defaultChange createParametrised destroyParametrised

cellWithActionParametrized
  :: forall a b . State Int b
  -> Cell Identity Bool (String, Int)
cellWithActionParametrized action
  = flip runStateC 0
  $ runHandlingStateC
  $ handlingParametrised testParametrisedHandle >>> arrM (<$ lift action)

test = testGroup "Handle"
  [ testProperty "Preserve Handles" CellMigrationSimulation
    { cell1 = cellWithAction $ modify (+ 1)
    , cell2 = cellWithAction $ return ()
    , input1 = replicate 3 ()
    , input2 = replicate 3 ()
    , output1 = ("Handle #0", ) <$> [1, 2, 3]
    , output2 = ("Handle #0", ) <$> [3, 3, 3]
    }
  , testProperty "Initialise Handles upon migration" CellMigrationSimulation
    { cell1 = flip runStateC 0 $ constM $ modify (+ 1) >> return ""
    , cell2 = cellWithAction $ return ()
    , input1 = replicate 3 ()
    , input2 = replicate 3 ()
    , output1 = ("", ) <$> [1, 2, 3]
    , output2 = ("Handle #3", ) <$> [3, 3, 3]
    }
  , testProperty "Preserve Handles in more complex migration" CellMigrationSimulation
    { cell1 = flip runStateC 22
        $ constM (modify (+ 1)) >>> runHandlingStateC (handling testHandle)
    , cell2 = cellWithAction $ return ()
    , input1 = replicate 3 ()
    , input2 = replicate 3 ()
    , output1 = ("Handle #23", ) <$> [23, 24, 25]
    , output2 = ("Handle #23", ) <$> replicate 3 25
    }
  , testProperty "Reinitialise Handles in too complex migration" CellMigrationSimulation
    { cell1 = flip runStateC 22
        $   constM (modify (+ 1))
        >>> constM get >>> sumC >>> sumC
        >>> runHandlingStateC (handling testHandle)
    , cell2 = cellWithAction $ return ()
    , input1 = replicate 3 ()
    , input2 = replicate 3 ()
    , output1 = ("Handle #23", ) <$> [23, 24, 25]
    , output2 = ("Handle #25", ) <$> replicate 3 25
    }
  , testProperty "Doesn't crash when handle is introspected by migration" CellMigrationSimulation
    { cell1 = cellWithAction $ return ()
    , cell2 = flip runStateC 0 $ runHandlingStateC
        $ handling testUnitHandle >>> arr (const "")
    , input1 = replicate 3 ()
    , input2 = replicate 3 ()
    , output1 = ("Handle #0", ) <$> replicate 3 0
    , output2 = ("", ) <$> replicate 3 10000
    }
  , testProperty "Trigger destructors" CellMigrationSimulation
    { cell1 = cellWithAction $ return ()
    , cell2 = flip runStateC 23
        $ runHandlingStateC $ arr $ const "Done"
    , input1 = replicate 3 ()
    , input2 = replicate 3 ()
    , output1 = ("Handle #0", ) <$> replicate 3 0
    , output2 = ("Done", ) <$> replicate 3 10000
    }
  , testProperty "Changing parameters triggers destructors" CellSimulation
    { cell = cellWithActionParametrized $ modify (+ 1)
    , input = [True, True, False, False]
    , output =
        [ ("Ye Olde Handle No 0", 1)
        , ("Ye Olde Handle No 0", 2)
        , ("Crazy new hdl #12345", 12346)
        , ("Crazy new hdl #12345", 12347)
        ]
    }
  , testProperty "Control flow does not trigger destructors or constructors" CellSimulation
    { cell = cellWithAction (modify (+ 1)) ||| arr (const ("Nope", 23))
    , input = [Right (), Left (), Left (), Right (), Left ()]
    , output =
        [ ("Nope", 23)
        , ("Handle #0", 1)
        , ("Handle #0", 2)
        , ("Nope", 23)
        , ("Handle #0", 3)
        ]

    }
  , Handle.LiveProgram.test
  ]
