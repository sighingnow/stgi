{-# LANGUAGE OverloadedLists   #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

-- TODO: list equality

module Stg.Language.Prelude.List (
    nil,
    concat,
    foldl,
    foldl',
    foldr,
    iterate,
    cycle,
    take,
    filter,
    repeat,
    sort,
    map,
    listIntEquals,

    -- * Convenience
    listOfNumbers,
) where



import qualified Prelude                     as P

import qualified Data.Map                    as M
import           Data.Monoid
import qualified Data.Text                   as T

import           Stg.Language
import           Stg.Parser
import           Stg.Util

import           Stg.Language.Prelude.Number as Num



nil, concat, foldl, foldl', foldr, iterate, cycle, take, filter, repeat, sort, map, listIntEquals :: Program

nil = [stg| nil = () \n () -> Nil () |]

concat = [stg|
    concat = () \n (xs,ys) -> case xs () of
        Nil () -> ys ();
        Cons (x,xs') ->
            let rest = (xs', ys) \u () -> concat (xs', ys)
            in Cons (x, rest);
        def -> Error_concat (def)
    |]

-- | Lazy left list fold.
--
-- @
-- foldl : (b -> a -> b) -> b -> [a] -> b
-- @
foldl = [stg|
    foldl = () \n (f, acc, xs) -> case xs () of
        Nil () -> acc ();
        Cons (y,ys) ->
            let acc' = (f,acc,y) \u () -> case f (acc, y) of
                    v -> v ()
            in foldl (f, acc', ys);
        default -> Error_foldl () |]

-- | Strict left list fold.
--
-- @
-- foldl' : (b -> a -> b) -> b -> [a] -> b
-- @
foldl' = [stg|
    foldl' = () \n (f, acc, xs) -> case xs () of
        Nil () -> acc ();
        Cons (y,ys) -> case f (acc, y) of
            acc' -> foldl' (f, acc', ys);
        default -> Error_foldl' ()
    |]

-- | Right list fold.
--
-- @
-- foldr : (a -> b -> b) -> b -> [a] -> b
-- @
foldr = [stg|
    foldr = () \n (f, z, xs) -> case xs () of
        Nil () -> z ();
        Cons (y,ys) ->
            let rest = (f,z,ys) \u () -> foldr (f,z,ys)
            in f (y, rest);
        default -> Error_foldr () |]

-- | Build a list by repeatedly applying a function to an initial value.
--
-- @
-- iterate f x = [x, f x, f (f x), ...]
-- @
--
-- @
-- iterate : (a -> a) -> a -> [a]
-- @
iterate = [stg|
    iterate = () \n (f,x) ->
        letrec fx = (f,x) \u () -> f (x);
               rest = (f,fx) \u () -> iterate (f,fx)
        in Cons (x,rest) |]

-- | Infinite list, created by repeating an initial (non-empty) list.
--
-- @
-- cycle [x,y,z] = [x,y,z, x,y,z, x,y,z, ...]
-- @
--
-- @
-- cycle : [a] -> [a]
-- @
cycle = concat <> [stg|
    cycle = () \n (xs) ->
        letrec xs' = (xs, xs') \u () -> concat (xs, xs')
        in xs' ()
    |]

-- | Take n elements form the beginning of a list.
--
-- @
-- take : Int -> [a] -> [a]
-- @
take = Num.add <> [stgProgram|
    take = () \u () ->
        letrec  minusOne = () \n () -> Int# (-1#);
                take' = (minusOne) \n (n, xs) -> case n () of
                    Int# (nPrim) -> case nPrim () of
                        0# -> Nil ();
                        default ->
                            let n' = (n, minusOne) \u () -> add (n, minusOne)
                            in case xs () of
                               Nil () -> Nil ();
                               Cons (y,ys) ->
                                   let rest = (n', ys) \u () -> take (n', ys)
                                   in Cons (y, rest);
                               default -> Error_take_not_a_list ();
                    default -> Error_take_not_an_int ()
        in take' ()
    |]

-- | Keep only the elements for which a predicate holds.
--
-- @
-- filter even [1..] = [2, 4, 6, ...]
-- @
--
-- @
-- filter : (a -> Bool) -> [a] -> [a]
-- @
filter = [stg|
    filter = () \n (p, xs) -> case xs () of
        Nil () -> Nil ();
        Cons (x,xs') -> case p (x) of
            False () -> filter (p, xs');
            True () ->
                let rest = (p, xs') \u () -> filter (p, xs')
                in Cons (x, rest);
            def -> Error_filter_1 (def);
        def -> Error_filter_2 (def)
    |]

-- | Repeat a single element infinitely.
--
-- @
-- repeat 1 = [1, 1, 1, ...]
-- @
--
-- @
-- repeat : a -> [a]
-- @
repeat = [stg|
    repeat = () \n (x) ->
        letrec xs = (x, xs) \u () -> Cons (x,xs)
        in xs ()
    |]

-- | That Haskell sort function often misleadingly referred to as "quicksort".
--
-- @
-- sort : [Int] -> [Int]
-- @
sort = mconcat [leq, gt, filter, concat] <> [stgProgram|
    sort = () \n (xs) -> case xs () of
        Nil () -> Nil ();
        Cons (pivot,xs') ->
            let beforePivotSorted = (pivot, xs') \u () ->
                    letrec
                        atMostPivot = (pivot) \n (y) -> leq_Int (y,pivot);
                        beforePivot = (xs', atMostPivot) \u () -> filter (atMostPivot, xs')
                    in sort (beforePivot);

                afterPivotSorted = (pivot, xs') \u () ->
                    letrec
                        moreThanPivot = (pivot) \n (y) -> gt_Int (y,pivot);
                        afterPivot    = (xs', moreThanPivot) \u () -> filter (moreThanPivot,  xs')
                    in sort (afterPivot)
            in  let fromPivotOn = (pivot, afterPivotSorted) \u () -> Cons (pivot, afterPivotSorted)
                in concat (beforePivotSorted, fromPivotOn);
        badList -> Error_sort (badList)
    |]

-- TODO: list :: [a] -> Program

-- | Apply a function to each element of a list.
--
-- @
-- map : (a -> b) -> [a] -> [b]
-- @
map = [stg|
    map = () \n (f, list) -> case list () of
        Nil ()       -> Nil ();
        Cons (x, xs) -> let fx  = (f, x)  \u () -> f (x);
                            fxs = (f, xs) \u () -> map (f, xs)
                        in  Cons (fx, fxs);
        default -> Error_Map ()
    |]

-- | Generate a list of numbers.
--
-- @
-- listOfNumbers [1, -2, 3]
-- @
--
-- @
-- numbers = () \u () ->
--     letrec  int_1 = () \n () -> Int\# (1\#);
--             int_3 = () \n () -> Int\# (3\#);
--             int_neg2 = () \n () -> Int\# (-2\#);
--             list_int_1 = (int_1,list_int_neg2) \u () -> Cons (int_1,list_int_neg2);
--             list_int_3 = (int_3,nil) \u () -> Cons (int_3,nil);
--             list_int_neg2 = (int_neg2,list_int_3) \u () -> Cons (int_neg2,list_int_3)
--     in list_int_1 ()
-- @
listOfNumbers
    :: T.Text      -- ^ Name of the list in the STG program
    -> [P.Integer] -- ^ Entries
    -> Program
-- TODO: The paper mentions a more efficient construction of literal source
-- lists that is "usually superior".
listOfNumbers name [] = nil <> Program (Binds [(Var name, [stg| () \n () -> nil () |])])
listOfNumbers name ints = nil <>
    Program (Binds [
        ( Var name
        , LambdaForm [] Update []
            (Let Recursive
                (Binds (M.fromList (intBinds <> listBinds)))
                (AppF (Var (listBindName (P.head ints))) []) ))])
  where
    intBinds = P.map intBind ints
    listBinds = P.zipWith listBind
                          ints
                          (P.map listBindName (P.tail ints) <> ["nil"])

    listBind i tailName =
        ( Var (listBindName i)
        , LambdaForm ([Var (intName i)] <> [ Var tailName | tailName P./= "nil"])
                     Update
                     []
                     ((AppC (Constr "Cons")
                            [AtomVar (Var (intName i)),AtomVar (Var tailName)] )))
    listBindName i = "list_" <> intName i

    intBind :: P.Integer -> (Var, LambdaForm)
    intBind i =
        ( Var (intName i)
        , LambdaForm [] NoUpdate []
                     (AppC (Constr "Int#") [AtomLit (Literal i)]))

    intName :: P.Integer -> T.Text
    intName i = "int_" <> sign <> show' (P.abs i)
      where
        sign | i P.< 0 = "'"
             | P.otherwise = ""

-- | Equality of lists of integers.
--
-- @
-- map : [Int] -> [Int] -> Bool
-- @
listIntEquals = Num.eq <> [stgProgram|
    listIntEquals = () \n (xs, ys) ->
        case xs () of
            Nil () -> case ys () of
                Nil () -> True ();
                Cons (y,ys') -> False ();
                v -> Error_listEquals (v);
            Cons (x,xs') -> case ys () of
                Nil () -> False ();
                Cons (y,ys') -> case eq_Int (x,y) of
                    True () -> listIntEquals (xs',ys');
                    False () -> False ();
                    default -> Error_listEquals_1 ();
                v -> Error_listEquals_2 (v);
            v -> Error_listEquals_3 (v)
    |]