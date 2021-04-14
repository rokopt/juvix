-- | This module serves as the main sexpression import it contains the
-- sexp type and all the various helper functionality one can need
module Juvix.Library.Sexp
  ( module Juvix.Library.Sexp.Types,
    module Juvix.Library.Sexp.Parser,
    foldPred,
    foldr,
    foldr1,
    butLast,
    last,
    list,
    listStar,
    addMetaToCar,
    car,
    cdr,
    atom,
    number,
    isAtomNamed,
    nameFromT,
    atomFromT,
    groupBy2,
    assoc,
    cadr,
    foldSearchPred,
    unGroupBy2,
    listStarAcc,
    append
  )
where

import Juvix.Library hiding (foldr, list, show, toList, length)
import qualified Juvix.Library.NameSymbol as NameSymbol
import Juvix.Library.Sexp.Parser
import Juvix.Library.Sexp.Types
{-@ LIQUID "--full" @-}

-- | @foldSearchPred@ is like foldPred with some notable exceptions.
-- 1. Instead of recusing on the @predChange@ form, it will just leave
--    the main form in tact.
--    - This is because in this sort of task we
--      will wish to maybe just change an aspect of it but maybe not
--      the actual form!
-- 2. We have a @predBind@ predicate which allows us to tell it what
--    forms can cause binders. This is useful when we care about what
--    is in scope for doing certain changes.
--
-- 3. In the case where both predicates match, then we will run the
--    binder and then the actual transformation, this is to ensure the
--    lexical semantics are respected, and then we can cleanup after
--    this.
--
-- 4. If the @predChange@ function accepts ":atom", then the function
--    will also be ran on the atom
--
-- For arguments, this function takes a Sexp, along with 2 sets of
-- pred function pairs. The function for the binding we take a
-- continuation, as it's not easy to automate the recursive calls in
-- instances such as case, so we have to do it by hand for those
-- binder cases
foldSearchPred ::
  Monad f =>
  T ->
  (NameSymbol.T -> Bool, Atom -> T -> f T) ->
  (NameSymbol.T -> Bool, Atom -> T -> (T -> f T) -> f T) ->
  f T
foldSearchPred t p1@(predChange, f) p2@(predBind, g) =
  case t of
    Cons a@(Atom atom@(A name _)) xs
      -- this case is a bit special as we wish to remove the form but
      -- it's a binder! So we must run it then run the transform on it!
      | predBind name && predChange name -> do
        bindedTerm <- bindCase
        changeCase (cdr bindedTerm)
      | predChange name -> changeCase xs
      | predBind name -> bindCase
      where
        changeCase xs = do
          newCons <- f atom xs
          case newCons of
            Cons _ _ ->
              Cons (car newCons) <$> foldSearchPred (cdr newCons) p1 p2
            _ ->
              pure newCons
        -- G takes the computation, as its changes are scoped over the
        -- calls.
        bindCase =
          Cons a <$> g atom xs (\xs -> foldSearchPred xs p1 p2)
    Cons cs xs ->
      Cons <$> foldSearchPred cs p1 p2 <*> foldSearchPred xs p1 p2
    Nil -> pure Nil
    Atom a
      | predChange ":atom" -> f a t
      | otherwise -> pure $ Atom a

foldPred :: T -> (NameSymbol.T -> Bool) -> (Atom -> T -> T) -> T
foldPred t pred f =
  case t of
    Cons (Atom atom@(A name _)) xs
      | pred name ->
        foldPred (f atom xs) pred f
    Cons cs xs ->
      Cons (foldPred cs pred f) (foldPred xs pred f)
    Nil -> Nil
    Atom a -> Atom a

foldr :: (T -> p -> p) -> p -> T -> p
foldr f acc ts =
  case ts of
    Cons a as -> f a (foldr f acc as)
    Atom ____ -> f ts acc
    Nil -> acc


foldr1 :: (T -> T -> T) -> T -> Maybe T
foldr1 f (Cons x xs) = Just $ unsafe (Cons x xs)
  where
    unsafe ts =
      case ts of
        Cons a Nil -> a
        Cons a cds -> f a (unsafe cds)
        _ -> error "doesn't happen"
foldr1 _ _empty = Nothing

butLast :: T -> T
butLast (Cons _ Nil) = Nil
butLast (Cons x xs) = Cons x (butLast xs)
butLast (Atom a) = Atom a
butLast Nil = Nil

last :: T -> T
last (Cons x Nil) = x
last (Cons _ xs) = last xs
last (Atom a) = Atom a
last Nil = Nil

{-@ list :: xs : [T] -> {v : T | lengthM v == len xs } @-}
list :: [T] -> T
list (x : xs) = Cons x (list xs)
list [] = Nil


-- TODO ∷ get a good refinement measurement on this
-- {-@ assume listStar ::
--  xs : [T]
--  -> { v : T |
--       ((NonNull xs) => lengthM v >= (lengthL xs - 1) + lengthM (lastList xs))
--    }
-- @-}
listStar :: [T] -> T
listStar =
  fromMaybe Nil . foldr1May Cons
  -- case reverse xs of
  --   (last : butLast) -> listStarAcc (reverse butLast) last
  --   [] -> Nil


{-@ listStarAcc
  :: xs : [T]
  -> acc : T
  -> { v : T |
       lengthM v == lengthL xs + lengthM acc
    }
@-}
listStarAcc :: [T] -> T -> T
listStarAcc (x : xs) acc = Cons x (listStarAcc xs acc)
listStarAcc [] acc = acc


addMetaToCar :: Atom -> T -> T
addMetaToCar (A _ lineInfo) (Cons (Atom (A term _)) xs) =
  Cons (Atom (A term lineInfo)) xs
addMetaToCar _ xs = xs

car :: T -> T
car (Cons x _) = x
car Nil = Nil
car (Atom a) = Atom a

cdr :: T -> T
cdr (Cons _ xs) = xs
cdr Nil = Nil
cdr (Atom a) = Atom a

cadr :: T -> T
cadr = car . cdr

atom :: NameSymbol.T -> T
atom x = Atom $ A x Nothing

number :: Integer -> T
number n = Atom $ N n Nothing

isAtomNamed :: T -> NameSymbol.T -> Bool
isAtomNamed (Atom (A name _)) name2 = name == name2
isAtomNamed _ _ = False

atomFromT :: T -> Maybe Atom
atomFromT (Atom a) = Just a
atomFromT _ = Nothing

nameFromT :: T -> Maybe NameSymbol.T
nameFromT (Atom (A name _)) = Just name
nameFromT _ = Nothing

-- Ill terminated lists do not work
-- TODO ∷ specify it out of this somehow
{-@ append :: xs : T -> ys : T -> {zs : T | lengthM zs == lengthM ys + lengthM xs } @-}
append :: T -> T -> T
append Nil ys = ys
append (Cons x xs) ys = Cons x (append xs ys)
append (Atom {}) ys = ys


assoc :: T -> T -> Maybe T
assoc t (car' :> cdr')
  | t == car car' = Just (cadr car')
  | otherwise = assoc t cdr'
assoc _ Nil = Nothing
assoc _ Atom {} = Nothing

groupBy2 :: T -> T
groupBy2 (a1 :> a2 :> rest) =
  list [a1, a2] :> groupBy2 rest
groupBy2 _ = Nil

unGroupBy2 :: T -> T
unGroupBy2 (List [a1, a2] :> rest) =
  a1 :> a2 :> unGroupBy2 rest
unGroupBy2 (a :> rest) =
  a :> unGroupBy2 rest
unGroupBy2 a = a


{-@ type Pos = {v:Int | 0 < v} @-}

{-@ incr :: {v:Int | 1 < v} -> Pos @-}
incr :: Int -> Int
incr x = x - 1


{-@ type Test = {s : T | lengthM s <= 4 } @-}

{-@ test :: Test @-}
test :: T
test =
  list [atom "type", atom "test2"]

{-@ foo' :: Test @-}
foo' :: T
foo' = Cons (number 3) (Cons (number 4) Nil)

{-@ foo :: {x : [Int] | lengthL x == 4} @-}
foo :: [Int]
foo = [1,2,3,4]

{-@ alistTest :: {x : T | lengthM x == 2 } @-}
alistTest :: T
alistTest = listStarAcc [atom "fi", number 3] (list [])

-- {-@ alistTest2 :: {x : T | lengthM x == 2 } @-}
alistTest2 :: T
alistTest2 = listStar [atom "fi", number 3, list []]
