{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE LambdaCase                #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE StandaloneDeriving        #-}
{-# LANGUAGE TypeApplications          #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeInType                #-}
{-# LANGUAGE TypeSynonymInstances      #-}
{-# LANGUAGE UndecidableInstances      #-}

module Learn.Neural.Layer.Recurrent.FullyConnected (
    FullyConnectedR
  , FullyConnectedR'
  , CommonMap(..)
  , MapFunc(..)
  ) where

import           Data.Kind
import           Data.Proxy
import           Data.Reflection
import           GHC.Generics                   (Generic)
import           GHC.TypeLits
import           Learn.Neural.Layer
import           Learn.Neural.Layer.Mapping
import           Numeric.BLASTensor
import           Numeric.Backprop
import           Numeric.Backprop.Iso           (iso)
import           Numeric.Backprop.Op
import           Statistics.Distribution
import           Statistics.Distribution.Normal
import qualified Generics.SOP                   as SOP

data FullyConnectedR :: Type

deriving instance Generic (CParam FullyConnectedR b (BV i) (BV o))
instance SOP.Generic (CParam FullyConnectedR b (BV i) (BV o))

instance (Num (b (BM o o)), Num (b (BM o i)), Num (b (BV o)))
      => Num (CParam FullyConnectedR b (BV i) (BV o)) where
    FCRP wI1 wS1 b1 + FCRP wI2 wS2 b2 = FCRP (wI1 + wI2) (wS1 + wS2) (b1 + b2)
    FCRP wI1 wS1 b1 - FCRP wI2 wS2 b2 = FCRP (wI1 - wI2) (wS1 - wS2) (b1 - b2)
    FCRP wI1 wS1 b1 * FCRP wI2 wS2 b2 = FCRP (wI1 * wI2) (wS1 * wS2) (b1 * b2)
    negate (FCRP wI wS b) = FCRP (negate wI) (negate wS) (negate b)
    signum (FCRP wI wS b) = FCRP (signum wI) (signum wS) (signum b)
    abs    (FCRP wI wS b) = FCRP (abs    wI) (abs    wS) (abs    b)
    fromInteger x = FCRP (fromInteger x) (fromInteger x) (fromInteger x)

instance Num (b (BV o)) => Num (CState FullyConnectedR b (BV i) (BV o)) where
    FCRS s1 + FCRS s2 = FCRS (s1 + s2)
    FCRS s1 - FCRS s2 = FCRS (s1 - s2)
    FCRS s1 * FCRS s2 = FCRS (s1 * s2)
    negate (FCRS s) = FCRS (negate s)
    signum (FCRS s) = FCRS (signum s)
    abs    (FCRS s) = FCRS (abs    s)
    fromInteger x  = FCRS (fromInteger x)


instance (KnownNat i, KnownNat o) => Component FullyConnectedR (BV i) (BV o) where
    data CParam  FullyConnectedR b (BV i) (BV o) =
            FCRP { _fcrInpWeights   :: !(b (BM o i))
                 , _fcrStateWeights :: !(b (BM o o))
                 , _fcrBiases       :: !(b (BV o))
                 }
    data CState  FullyConnectedR b (BV i) (BV o) = FCRS { _fcrState :: !(b (BV o)) }
    type CConstr FullyConnectedR b (BV i) (BV o) = (Num (b (BM o i)), Num (b (BM o o)))
    data CConf   FullyConnectedR   (BV i) (BV o) = forall d. ContGen d => FCRC d

    componentOp = bpOp . withInps $ \(x :< p :< s :< Ø) -> do
        wI :< wS :< b :< Ø <- gTuple #<~ p
        s0 <- opIso (iso _fcrState FCRS) ~$ (s :< Ø)
        y  <- matVecOp ~$ (wI :< x  :< Ø)
        s1 <- matVecOp ~$ (wS :< s0 :< Ø)
        z  <- bindVar $ y + s1 + b
        s' <- opIso (iso FCRS _fcrState) ~$ (s1 :< Ø)
        return $ z :< s' :< Ø

    defConf = FCRC (normalDistr 0 0.5)
    initParam (SBV i) so@(SBV o) (FCRC d) g = do
        wI <- genA (SBM o i) $ \_ ->
          realToFrac <$> genContVar d g
        wS <- genA (SBM o o) $ \_ ->
          realToFrac <$> genContVar d g
        b <- genA so $ \_ ->
          realToFrac <$> genContVar d g
        return $ FCRP wI wS b
    initState _ so (FCRC d) g =
        FCRS <$> genA so (\_ -> realToFrac <$> genContVar d g)

instance (KnownNat i, KnownNat o) => ComponentLayer 'Recurrent FullyConnectedR (BV i) (BV o) where
    componentRunMode = RMNotFF

data FullyConnectedR' :: k -> Type

deriving instance Generic (CParam (FullyConnectedR' c) b (BV i) (BV o))
instance SOP.Generic (CParam (FullyConnectedR' c) b (BV i) (BV o))

instance (Num (b (BM o o)), Num (b (BM o i)), Num (b (BV o)))
      => Num (CParam (FullyConnectedR' s) b (BV i) (BV o)) where
    FCRP' wI1 wS1 b1 + FCRP' wI2 wS2 b2 = FCRP' (wI1 + wI2) (wS1 + wS2) (b1 + b2)
    FCRP' wI1 wS1 b1 - FCRP' wI2 wS2 b2 = FCRP' (wI1 - wI2) (wS1 - wS2) (b1 - b2)
    FCRP' wI1 wS1 b1 * FCRP' wI2 wS2 b2 = FCRP' (wI1 * wI2) (wS1 * wS2) (b1 * b2)
    negate (FCRP' wI wS b) = FCRP' (negate wI) (negate wS) (negate b)
    signum (FCRP' wI wS b) = FCRP' (signum wI) (signum wS) (signum b)
    abs    (FCRP' wI wS b) = FCRP' (abs    wI) (abs    wS) (abs    b)
    fromInteger x = FCRP' (fromInteger x) (fromInteger x) (fromInteger x)

instance Num (b (BV o)) => Num (CState (FullyConnectedR' s) b (BV i) (BV o)) where
    FCRS' s1 + FCRS' s2 = FCRS' (s1 + s2)
    FCRS' s1 - FCRS' s2 = FCRS' (s1 - s2)
    FCRS' s1 * FCRS' s2 = FCRS' (s1 * s2)
    negate (FCRS' s) = FCRS' (negate s)
    signum (FCRS' s) = FCRS' (signum s)
    abs    (FCRS' s) = FCRS' (abs    s)
    fromInteger x  = FCRS' (fromInteger x)


instance (KnownNat i, KnownNat o, Reifies s MapFunc)
      => Component (FullyConnectedR' s) (BV i) (BV o) where
    data CParam  (FullyConnectedR' c) b (BV i) (BV o) =
            FCRP' { _fcrInpWeights'   :: !(b (BM o i))
                  , _fcrStateWeights' :: !(b (BM o o))
                  , _fcrBiases'       :: !(b (BV o))
                  }
    data CState  (FullyConnectedR' c) b (BV i) (BV o) = FCRS' { _fcrState' :: !(b (BV o)) }
    type CConstr (FullyConnectedR' c) b (BV i) (BV o) =
      ( Num (b (BM o i))
      , Num (b (BM o o))
      )
    data CConf   (FullyConnectedR' c)   (BV i) (BV o) = forall d. ContGen d => FCRC' d

    componentOp = bpOp . withInps $ \(x :< p :< s :< Ø) -> do
        wI :< wS :< b :< Ø <- gTuple #<~ p
        s0 <- opIso (iso _fcrState' FCRS') ~$ (s :< Ø)
        y  <- matVecOp ~$ (wI :< x  :< Ø)
        s1 <- matVecOp ~$ (wS :< s0 :< Ø)
        z  <- bindVar $ y + s1 + b
        s2 <- tmapOp (runMapFunc mf) ~$ (s1 :< Ø)
        s' <- opIso (iso FCRS' _fcrState') ~$ (s2 :< Ø)
        return $ z :< s' :< Ø
      where
        mf :: MapFunc
        mf = reflect (Proxy @s)

    defConf = FCRC' (normalDistr 0 0.5)

    initParam (SBV i) so@(SBV o) (FCRC' d) g = do
        wI <- genA (SBM o i) $ \_ ->
          realToFrac <$> genContVar d g
        wS <- genA (SBM o o) $ \_ ->
          realToFrac <$> genContVar d g
        b <- genA so $ \_ ->
          realToFrac <$> genContVar d g
        return $ FCRP' wI wS b

    initState _ so (FCRC' d) g =
        FCRS' <$> genA so (\_ -> realToFrac <$> genContVar d g)

instance (KnownNat i, KnownNat o, Reifies s MapFunc)
      => ComponentLayer 'Recurrent (FullyConnectedR' s) (BV i) (BV o) where
    componentRunMode = RMNotFF

