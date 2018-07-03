{-# LANGUAGE DataKinds                                #-}
{-# LANGUAGE DeriveDataTypeable                       #-}
{-# LANGUAGE DeriveGeneric                            #-}
{-# LANGUAGE FlexibleInstances                        #-}
{-# LANGUAGE GADTs                                    #-}
{-# LANGUAGE KindSignatures                           #-}
{-# LANGUAGE MultiParamTypeClasses                    #-}
{-# LANGUAGE PatternSynonyms                          #-}
{-# LANGUAGE RankNTypes                               #-}
{-# LANGUAGE RecordWildCards                          #-}
{-# LANGUAGE ScopedTypeVariables                      #-}
{-# LANGUAGE TemplateHaskell                          #-}
{-# LANGUAGE TypeApplications                         #-}
{-# LANGUAGE TypeFamilies                             #-}
{-# LANGUAGE TypeInType                               #-}
{-# LANGUAGE TypeOperators                            #-}
{-# LANGUAGE UndecidableInstances                     #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}

module Backprop.Learn.Model.Neural.LSTM (
    -- * LSTM
    lstm
  , LSTMp(..), lstmForget, lstmInput, lstmUpdate, lstmOutput
    -- * GRU
  , gru
  , GRUp(..), gruMemory, gruUpdate, gruOutput
  ) where

import           Backprop.Learn.Initialize
import           Backprop.Learn.Model.Function
import           Backprop.Learn.Model.Neural
import           Backprop.Learn.Model.Regression
import           Backprop.Learn.Model.State
import           Backprop.Learn.Model.Types
import           Control.DeepSeq
import           Data.Type.Tuple
import           Data.Typeable
import           GHC.Generics                          (Generic)
import           GHC.TypeNats
import           Lens.Micro
import           Lens.Micro.TH
import           Numeric.Backprop
import           Numeric.LinearAlgebra.Static.Backprop
import           Numeric.OneLiner
import           Numeric.Opto.Ref
import           Numeric.Opto.Update
import qualified Data.Binary                           as Bi
import qualified Numeric.LinearAlgebra.Static          as H

-- TODO: allow parameterize internal activation function?
-- TODO: Peepholes

-- | 'LSTM' layer parmateters
data LSTMp (i :: Nat) (o :: Nat) =
    LSTMp { _lstmForget :: !(FCp (i + o) o)
          , _lstmInput  :: !(FCp (i + o) o)
          , _lstmUpdate :: !(FCp (i + o) o)
          , _lstmOutput :: !(FCp (i + o) o)
          }
  deriving (Generic, Typeable, Show)

makeLenses ''LSTMp

instance NFData (LSTMp i o)
instance (KnownNat i, KnownNat o) => Additive (LSTMp i o)
instance (KnownNat i, KnownNat o) => Scaling Double (LSTMp i o)
instance (KnownNat i, KnownNat o) => Metric Double (LSTMp i o)
instance (KnownNat i, KnownNat o, Ref m (LSTMp i o) v) => AdditiveInPlace m v (LSTMp i o)
instance (KnownNat i, KnownNat o, Ref m (LSTMp i o) v) => ScalingInPlace m v Double (LSTMp i o)
instance (KnownNat i, KnownNat o) => Bi.Binary (LSTMp i o)
instance (KnownNat i, KnownNat o) => Backprop (LSTMp i o)

lstm'
    :: (KnownNat i, KnownNat o)
    => Model ('Just (LSTMp i o)) ('Just (R o)) (R (i + o)) (R o)
lstm' = modelD $ \(J_ p) x (J_ s) ->
    let forget = logistic $ runLRp (p ^^. lstmForget) x
        input  = logistic $ runLRp (p ^^. lstmInput ) x
        update = tanh     $ runLRp (p ^^. lstmUpdate) x
        s'     = forget * s + input * update
        o      = logistic $ runLRp (p ^^. lstmOutput) x
        h      = o * tanh s'
    in  (h, J_ s')

-- | Long-term short-term memory layer
--
-- <http://colah.github.io/posts/2015-08-Understanding-LSTMs/>
--
lstm
    :: (KnownNat i, KnownNat o)
    => Model ('Just (LSTMp i o)) ('Just (R o :& R o)) (R i) (R o)
lstm = recurrent H.split (H.#) id lstm'

-- | Forget biases initialized to 1
instance (KnownNat i, KnownNat o) => Initialize (LSTMp i o) where
    initialize d g = LSTMp <$> set (mapped . fcBias) 1 (initialize d g)
                           <*> initialize d g
                           <*> initialize d g
                           <*> initialize d g

instance (KnownNat i, KnownNat o) => Num (LSTMp i o) where
    (+)         = gPlus
    (-)         = gMinus
    (*)         = gTimes
    negate      = gNegate
    abs         = gAbs
    signum      = gSignum
    fromInteger = gFromInteger

instance (KnownNat i, KnownNat o) => Fractional (LSTMp i o) where
    (/)          = gDivide
    recip        = gRecip
    fromRational = gFromRational

instance (KnownNat i, KnownNat o) => Floating (LSTMp i o) where
    pi    = gPi
    sqrt  = gSqrt
    exp   = gExp
    log   = gLog
    sin   = gSin
    cos   = gCos
    asin  = gAsin
    acos  = gAcos
    atan  = gAtan
    sinh  = gSinh
    cosh  = gCosh
    asinh = gAsinh
    acosh = gAcosh
    atanh = gAtanh

-- | 'GRU' layer parmateters
data GRUp (i :: Nat) (o :: Nat) =
    GRUp { _gruMemory :: !(FCp (i + o) o)
         , _gruUpdate :: !(FCp (i + o) o)
         , _gruOutput :: !(FCp (i + o) o)
         }
  deriving (Generic, Typeable, Show)

makeLenses ''GRUp

instance NFData (GRUp i o)
instance (KnownNat i, KnownNat o) => Additive (GRUp i o)
instance (KnownNat i, KnownNat o) => Scaling Double (GRUp i o)
instance (KnownNat i, KnownNat o) => Metric Double (GRUp i o)
instance (KnownNat i, KnownNat o, Ref m (GRUp i o) v) => AdditiveInPlace m v (GRUp i o)
instance (KnownNat i, KnownNat o, Ref m (GRUp i o) v) => ScalingInPlace m v Double (GRUp i o)
instance (KnownNat i, KnownNat o) => Bi.Binary (GRUp i o)
instance (KnownNat i, KnownNat o) => Backprop (GRUp i o)

instance (KnownNat i, KnownNat o) => Initialize (GRUp i o) where
    initialize d g = GRUp <$> initialize d g
                          <*> initialize d g
                          <*> initialize d g

gru'
    :: forall i o. (KnownNat i, KnownNat o)
    => Model ('Just (GRUp i o)) 'Nothing (R (i + o)) (R o)
gru' = modelStatelessD $ \(J_ p) x ->
    let z      = logistic $ runLRp (p ^^. gruMemory) x
        r      = logistic $ runLRp (p ^^. gruUpdate) x
        r'     = 1 # r
        h'     = tanh     $ runLRp (p ^^. gruOutput) (r' * x)
    in  (1 - z) * snd (split @i x) + z * h'

-- | Gated Recurrent Unit
--
-- <http://colah.github.io/posts/2015-08-Understanding-LSTMs/>
--
gru :: (KnownNat i, KnownNat o)
    => Model ('Just (GRUp i o)) ('Just (R o)) (R i) (R o)
gru = recurrent H.split (H.#) id gru'

instance (KnownNat i, KnownNat o) => Num (GRUp i o) where
    (+)         = gPlus
    (-)         = gMinus
    (*)         = gTimes
    negate      = gNegate
    abs         = gAbs
    signum      = gSignum
    fromInteger = gFromInteger

instance (KnownNat i, KnownNat o) => Fractional (GRUp i o) where
    (/)          = gDivide
    recip        = gRecip
    fromRational = gFromRational

instance (KnownNat i, KnownNat o) => Floating (GRUp i o) where
    pi    = gPi
    sqrt  = gSqrt
    exp   = gExp
    log   = gLog
    sin   = gSin
    cos   = gCos
    asin  = gAsin
    acos  = gAcos
    atan  = gAtan
    sinh  = gSinh
    cosh  = gCosh
    asinh = gAsinh
    acosh = gAcosh
    atanh = gAtanh