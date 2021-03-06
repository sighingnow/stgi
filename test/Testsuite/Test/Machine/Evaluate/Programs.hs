{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE NumDecimals       #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

-- | Tests of medium size, defined by terminating within a certain number of
-- steps (configured in 'defSpec').

-- These tests will be run with garbage collection enabled, and should have the
-- scope of small functions a Haskell beginner might play around with.
module Test.Machine.Evaluate.Programs (tests) where



import Data.Foldable

import           Stg.Machine.Types
import           Stg.Marshal
import           Stg.Parser.QuasiQuoter
import qualified Stg.Prelude            as Stg

import           Test.Machine.Evaluate.TestTemplates.MachineState
import qualified Test.Machine.Evaluate.TestTemplates.MarshalledValue as MVal
import           Test.Machine.Evaluate.TestTemplates.Util
import           Test.Orphans                                        ()
import           Test.QuickCheck.Modifiers
import           Test.Tasty



tests :: TestTree
tests = testGroup "Programs"
    [ add3
    , takeRepeat
    , fibonacci
    , testGroup "mean of a list"
        [ meanNaive
        , meanNaiveWithFoldl'
        , meanGood ]
    ]

add3 :: TestTree
add3 = machineStateTest defSpec
    { testName = "add3 x y z = x+y+z"
    , successPredicate = "main" `hasValue` (6 :: Integer)
    , source = [stg|
        add3 = \x y z -> case x of
            Int# i -> case y of
                Int# j -> case +# i j of
                    ij -> case z of
                        Int# k -> case +# ij k of
                            ijk -> Int# ijk;
                        badInt -> Error_add3_1 badInt;
                badInt -> Error_add3_2 badInt;
            badInt -> Error_add3_3 badInt;

        one   = \ -> Int# 1#;
        two   = \ -> Int# 2#;
        three = \ -> Int# 3#;
        main = \ => add3 one two three
        |] }

takeRepeat :: TestTree
takeRepeat = machineStateTest defSpec
    { testName = "take 2 (repeat ())"
    , successPredicate = "twoUnits" `hasValue` replicate 2 ()
    , source = mconcat
        [ toStg "two" (2 :: Integer)
        , Stg.take
        , Stg.repeat
        , Stg.foldr
        , Stg.force
        , [stg|
        consBang = \x xs -> case xs of v -> Cons x v;
        nil = \ -> Nil;
        forceSpine = \xs -> foldr consBang nil xs;

        twoUnits = \ =>
            letrec
                repeated = \(unit) => repeat unit;
                unit = \ -> Unit;
                take2 = \(repeated) => take two repeated
            in forceSpine take2;

        main = \ -> force twoUnits
        |] ]}

fibonacci :: TestTree
fibonacci = machineStateTest defSpec
    { testName = "Fibonacci sequence"
    , successPredicate = "main" `hasValue` take numFibos fibo
    , maxSteps = 10000
    , source = mconcat
        [ toStg "zero" (0 :: Int)
        , toStg "one" (1 :: Int)
        , toStg "numFibos" (numFibos :: Int)
        , Stg.add
        , Stg.take
        , Stg.zipWith
        , Stg.force
        , [stg|
        main = \ =>
            letrec
                fibos = \(fibo) => take numFibos fibo;
                fibo = \ =>
                    letrec
                        fib0 = \(fib1) -> Cons zero fib1;
                        fib1 = \(fib2) -> Cons one fib2;
                        fib2 = \(fib0 fib1) => zipWith add fib0 fib1
                    in fib0
            in force fibos
        |] ]}
  where
    fibo :: [Integer]
    fibo = 0 : 1 : zipWith (+) fibo (tail fibo)
    numFibos :: Num a => a
    numFibos = 10

meanTestTemplate :: MVal.MarshalledValueTestSpec (NonEmptyList Integer) Integer
meanTestTemplate =
    let mean :: [Integer] -> Integer
        mean xs = let (total, count) = foldl' go (0,0) xs
                      go (!t, !c) x = (t+x, c+1)
                  in total `div` count
    in MVal.MarshalledValueTestSpec
        { MVal.testName = "Mena test template"
        , MVal.maxSteps = 1024
        , MVal.failWithInfo = False
        , MVal.failPredicate = const False
        , MVal.sourceSpec = \(NonEmpty inputList) -> MVal.MarshalSourceSpec
            { MVal.resultVar = "main"
            , MVal.expectedValue = mean inputList
            , MVal.source = mconcat
                [ Stg.add
                , Stg.div
                , toStg "zero" (0 :: Int)
                , toStg "one"  (1 :: Int)
                , toStg "inputList" inputList
                , [stg| main = \ => mean inputList |] ]}}

meanNaive :: TestTree
meanNaive = MVal.marshalledValueTest meanTestTemplate
    { MVal.testName = "Naïve: foldl and lazy tuple"
    , MVal.sourceSpec = \inputList -> (MVal.sourceSpec meanTestTemplate inputList)
        { MVal.source = mconcat
            [ MVal.source (MVal.sourceSpec meanTestTemplate inputList)
            , Stg.foldl
            , [stg|
            mean = \xs ->
                letrec
                    totals = \(go zeroTuple) -> foldl go zeroTuple;
                    zeroTuple = \ -> Tuple zero zero;
                    go = \acc x -> case acc of
                        Tuple t n ->
                            let tx = \(t x) => add t x;
                                n1 = \(n) => add n one
                            in Tuple tx n1;
                        badTuple -> Error_mean1 badTuple
                in case totals xs of
                    Tuple t n -> div t n;
                    badTuple -> Error_mean2 badTuple
            |] ]}}

meanNaiveWithFoldl' :: TestTree
meanNaiveWithFoldl' = MVal.marshalledValueTest meanTestTemplate
    { MVal.testName = "Naïve with insufficient optimization: foldl'"
    , MVal.sourceSpec = \inputList -> (MVal.sourceSpec meanTestTemplate inputList)
        { MVal.source = mconcat
            [ MVal.source (MVal.sourceSpec meanTestTemplate inputList)
            , Stg.foldl'
            , [stg|
            mean = \xs ->
                letrec
                    totals = \(go zeroTuple) -> foldl' go zeroTuple;
                    zeroTuple = \ -> Tuple zero zero;
                    go = \acc x -> case acc of
                        Tuple t n ->
                            let tx = \(t x) => add t x;
                                n1 = \(n) => add n one
                            in Tuple tx n1;
                        badTuple -> Error_mean1 badTuple
                in case totals xs of
                    Tuple t n -> div t n;
                    badTuple -> Error_mean2 badTuple
            |] ]}}

meanGood :: TestTree
meanGood = MVal.marshalledValueTest meanTestTemplate
    { MVal.testName = "Proper: foldl' and strict tuple"
    , MVal.failWithInfo = False
    , MVal.failPredicate = \stgState -> length (stgStack stgState) >= 9
    , MVal.sourceSpec = \inputList -> (MVal.sourceSpec meanTestTemplate inputList)
        { MVal.source = mconcat
            [ MVal.source (MVal.sourceSpec meanTestTemplate inputList)
            , Stg.foldl'
            , [stg|
            mean = \xs ->
                letrec
                    totals = \(go zeroTuple) -> foldl' go zeroTuple;
                    zeroTuple = \ -> Tuple zero zero;
                    go = \acc x -> case acc of
                        Tuple t n ->
                            let tx = \(t x) => add t x;
                                n1 = \(n) => add n one
                            in case tx of
                                default -> case n1 of
                                    default -> Tuple tx n1;
                        badTuple -> Error_mean1 badTuple
                in case totals xs of
                    Tuple t n -> div t n;
                    badTuple -> Error_mean2 badTuple
            |] ]}}
