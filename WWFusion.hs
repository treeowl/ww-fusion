{-# LANGUAGE RankNTypes, ScopedTypeVariables #-}
module WWFusion
  ( foldrW
  , buildW
  , foldl
  , foldl'
  , foldr
  , filter
  , map
  , eft
  , (++)
  , concat
  , dropWhile
  , reverse
  , scanl
  , Wrap(..)
  ) where

import Prelude hiding ((++), foldl, foldr, concat, filter, map, reverse, dropWhile, scanl)

data Wrap f b = Wrap (forall e. f e -> e -> b) (forall e. (e -> b) -> f e)

foldrW
  :: Wrap f b
  -> (a -> b -> b)
  -> b
  -> [a]
  -> b
foldrW (Wrap wrap unwrap) f z0 list0 = wrap go list0
  where
    go = unwrap $ \list -> case list of
      [] -> z0
      x:xs -> f x $ wrap go xs
{-# NOINLINE[0] foldrW #-}

newtype Simple b e = Simple { runSimple :: e -> b }

isoSimple :: Wrap (Simple b) b
isoSimple = Wrap runSimple Simple

foldr :: (a -> b -> b) -> b -> [a] -> b
foldr f z = foldrW isoSimple f z
{-# INLINE foldr #-}

buildW
  :: (forall b f . (Wrap f b)
    -> (a -> b -> b)
    -> b
    -> b)
  -> [a]
buildW g = g isoSimple (:) []
{-# INLINE[0] buildW #-}

augmentW
  :: (forall b f . (Wrap f b)
    -> (a -> b -> b)
    -> b
    -> b)
  -> [a]
  -> [a]
augmentW g xs = g isoSimple (:) xs
{-# INLINE[0] augmentW #-}

(++) :: [a] -> [a] -> [a]
a ++ b = augmentW (\i c n -> foldrW i c n a) b
{-# INLINE (++) #-}

concat :: [[a]] -> [a]
concat xs = buildW (\i c n -> foldrW i (\x y -> foldrW i c y x) n xs)
{-# INLINE concat #-}

foldl' :: (b -> a -> b) -> b -> [a] -> b
foldl' f initial = \xs -> foldrW wrapFoldl g id xs initial
  where g x next acc = next $! f acc x
{-# INLINE foldl' #-}

foldl :: (b -> a -> b) -> b -> [a] -> b
foldl f initial = \xs -> foldrW wrapFoldl g id xs initial
  where g x next acc = next $ f acc x
{-# INLINE foldl #-}

newtype Left b e = L { runL :: e -> b -> b }

wrapFoldl :: Wrap (Left b) (b -> b)
wrapFoldl = Wrap runL L

map :: (a -> b) -> [a] -> [b]
map f = \xs -> buildW (mapFB f xs)
{-# INLINE map #-}

mapFB
  :: (a -> b)
  -> [a]
  -> Wrap f r
  -> (b -> r -> r)
  -> r
  -> r
mapFB f xs = \ww cons nil -> foldrW ww (cons . f) nil xs
{-# INLINE mapFB #-}

filter :: (a -> Bool) -> [a] -> [a]
filter p = \xs -> buildW (filterFB p xs)
{-# INLINE filter #-}

filterFB
  :: (a -> Bool)
  -> [a]
  -> (Wrap f r)
  -> (a -> r -> r)
  -> r
  -> r
filterFB p xs ww cons nil = foldrW ww f nil xs
  where
    f x y = if p x then cons x y else y
{-# INLINE[0] filterFB #-}

eft :: Int -> Int -> [Int]
eft = \from to -> buildW (eftFB from to)
{-# INLINE eft #-}

eftFB
  :: Int
  -> Int
  -> (Wrap f r)
  -> (Int -> r -> r)
  -> r
  -> r
eftFB from to (Wrap wrap unwrap) cons nil = wrap go from
  where
    go = unwrap $ \i -> if i <= to
      then cons i $ wrap go (i + 1)
      else nil
{-# INLINE[0] eftFB #-}

dropWhile :: (a -> Bool) -> [a] -> [a]
dropWhile p xs = buildW $ dwFB p xs
{-# INLINE dropWhile #-}

dwFB :: (a -> Bool) -> [a] -> Wrap f r -> (a -> r -> r) -> r -> r
dwFB p xs = \w cons nil -> foldrW (dwWrap w) (dwCons p cons) (dwNil nil) xs True
{-# INLINE dwFB #-}

newtype Env r f e = Env { runEnv :: r -> f e }

dwWrap :: Wrap f r -> Wrap (Env s f) (s -> r)
dwWrap (Wrap wrap unwrap) = Wrap
  (\(Env h) e s -> wrap (h s) e)
  (\h -> Env $ \s -> unwrap $ \e -> h e s)
{-# INLINE[0] dwWrap #-}

dwNil :: r -> Bool -> r
dwNil r _ = r
{-# INLINE[0] dwNil #-}

dwCons :: (a -> Bool) -> (a -> r -> r) -> a -> (Bool -> r) -> (Bool -> r)
dwCons p c = \e k b -> let b' = b && p e in if b' then k b' else e `c` k b'
{-# INLINE[0] dwCons #-}

reverse :: [a] -> [a]
reverse xs = buildW $ revFB xs
{-# INLINE reverse #-}

revFB :: [a] -> Wrap f r -> (a -> r -> r) -> r -> r
revFB xs = \w cons nil -> foldrW (revWrap w) (revCons cons) id xs nil
{-# INLINE revFB #-}

revWrap :: Wrap f r -> Wrap (Env r f) (r -> r)
revWrap (Wrap wrap unwrap) = Wrap
  (\(Env h) e r -> wrap (h r) e)
  (\h -> Env $ \r -> unwrap $ \e -> h e r)
{-# INLINE[0] revWrap #-}

revCons :: (a -> r -> r) -> a -> (r -> r) -> r -> r
revCons c e k z = k (c e z)
{-# INLINE[0] revCons #-}

scanl :: (b -> a -> b) -> b -> [a] -> [b]
scanl f z xs = buildW (scanlFB f z xs)
{-# INLINE scanl #-}

scanlFB :: (b -> a -> b) -> b -> [a] -> Wrap f r -> (b -> r -> r) -> r -> r
scanlFB f z xs = \w c n -> foldrW (scanlWrap c w) (scanlCons f) (const n) xs z
{-# INLINE scanlFB #-}

scanlWrap :: (b -> r -> r) -> Wrap f r -> Wrap (Env b f) (b -> r)
scanlWrap cons (Wrap wrap unwrap) = Wrap
  (\(Env s) e b -> wrap (s b) e)
  (\u -> Env $ \b -> unwrap $ \e -> b `cons` u e b)
{-# INLINE[0] scanlWrap #-}

scanlCons :: (b -> a -> b) -> a -> (b -> r) -> b -> r
scanlCons f = \e k acc -> k (f acc e)
{-# INLINE[0] scanlCons #-}

{-# RULES
"foldrW/buildW" forall
    f z
    (i :: Wrap f b)
    (g :: forall c g .
      (Wrap g c)
      -> (a -> c -> c)
      -> c
      -> c)
    .
  foldrW i f z (buildW g) = g i f z
"foldrW/augmentW" forall
    f z
    (i :: forall e. Wrap (f e) (e -> b -> b))
    (g :: forall c g .
      (Wrap g c)
      -> (a -> c -> c)
      -> c
      -> c)
    xs
    .
  foldrW i f z (augmentW g xs) = g i f (foldrW i f z xs)
"augmentW/buildW" forall
    (f :: forall c g.
      (Wrap g c)
      -> (a -> c -> c)
      -> c
      -> c)
    (g :: forall c g .
      (Wrap g c)
      -> (a -> c -> c)
      -> c
      -> c)
    .
  augmentW g (buildW f) = buildW (\i c n -> g i c (f i c n))
  #-}
