{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeInType          #-}
{-# LANGUAGE TypeOperators       #-}

module Numeric.Tensor (
    Tensor(..)
  , tmapOp
  , tzipNOp
  , tkonstOp
  ) where

import           Data.Kind
import           Data.Reflection
import           Data.Singletons
import           Data.Type.Util
import           Data.Type.Vector hiding     (head')
import           Numeric.AD
import           Numeric.AD.Internal.Reverse
import           Numeric.AD.Mode.Forward     (Forward)
import           Numeric.Backprop.Op
import           Type.Class.Known
import qualified Data.Type.Nat               as TCN

class (SingKind k, RealFloat (ElemT t)) => Tensor (t :: k -> Type) where
    type IndexT t :: k -> Type
    type ElemT  t :: Type

    genA
        :: Applicative f
        => Sing s
        -> (IndexT t s -> f (ElemT t))
        -> f (t s)

    gen :: Sing s
        -> (IndexT t s -> ElemT t)
        -> t s

    tkonst :: Sing s -> ElemT t -> t s

    tsum :: SingI s => t s -> ElemT t
    tmap :: SingI s => (ElemT t -> ElemT t) -> t s -> t s
    tzip
        :: SingI s
        => (ElemT t -> ElemT t -> ElemT t)
        -> t s
        -> t s
        -> t s

    tzipN
        :: SingI s
        => (Vec n (ElemT t) -> ElemT t)
        -> VecT n t s
        -> t s

    tsize
        :: SingI s
        => t s
        -> Int

tmapOp
    :: (Tensor t, SingI s)
    => (forall q. AD q (Forward (ElemT t)) -> AD q (Forward (ElemT t)))
    -> Op '[t s] '[t s]
tmapOp f = op1' $ \x ->
    let y  = tmap (fst . diff' f) x
        dy = tmap (diff f) x
    in  (only_ y, maybe dy (tzip (*) dy) . head')

tzipNOp
    :: forall k t (s :: k) n. (Tensor t, SingI s, Known TCN.Nat n)
    => (forall q. Reifies q Tape => Vec n (Reverse q (ElemT t)) -> Reverse q (ElemT t))
    -> Op (Replicate n (t s)) '[t s]
tzipNOp f = Op $ \xs ->
    let n :: TCN.Nat n
        n = known
        xs' = vmap getI . prodToVec' n $ xs
        y   = tzipN (fst . grad' f) xs'
        dy  = vgen n $ \i -> I $ tzipN (index' i . grad f) xs'
    in  (only_ y, vecToProd . maybe dy (\g -> tzip (*) g <$> dy) . head')

tkonstOp :: forall t s. Tensor t => Sing s -> Op '[ElemT t] '[t s]
tkonstOp s = withSingI s $ op1' $ \x ->
    let res = tkonst s x
    in  (only_ res, maybe (fromIntegral (tsize res)) tsum . head')
