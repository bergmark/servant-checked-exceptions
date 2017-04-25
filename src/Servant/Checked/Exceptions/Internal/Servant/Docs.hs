{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Servant.Checked.Exceptions.Internal.Servant.Docs where

import Control.Lens ((&), (<>~))
import Data.Proxy (Proxy(Proxy))
import Data.ByteString.Lazy (ByteString)
import Data.Monoid ((<>))
import Data.Text (Text)
import Network.HTTP.Media (MediaType)
import Servant.API (Verb, (:>))
import Servant.API.ContentTypes (AllMimeRender(allMimeRender))
import Servant.Docs
       (Action, API, DocOptions, Endpoint, HasDocs(docsFor),
        ToSample(toSamples))
import Servant.Docs.Internal
       (DocNote(DocNote), apiEndpoints, notes, respBody, response)

import Servant.Checked.Exceptions.Internal.Envelope
       (Envelope, toErrEnvelope, toSuccEnvelope)
import Servant.Checked.Exceptions.Internal.Servant.API
       (Throws, Throwing)
import Servant.Checked.Exceptions.Internal.Util (Snoc)

instance (HasDocs (Throwing '[e] :> api)) => HasDocs (Throws e :> api) where
  docsFor
    :: Proxy (Throws e :> api)
    -> (Endpoint, Action)
    -> DocOptions
    -> API
  docsFor Proxy = docsFor (Proxy :: Proxy (Throwing '[e] :> api))

instance (CreateRespBodiesFor es ctypes, HasDocs (Verb method status ctypes (Envelope es a))) =>
    HasDocs (Throwing es :> Verb method status ctypes a) where
  docsFor
    :: Proxy (Throwing es :> Verb method status ctypes a)
    -> (Endpoint, Action)
    -> DocOptions
    -> API
  docsFor Proxy (endpoint, action) docOpts =
    let api =
          docsFor
            (Proxy :: Proxy (Verb method status ctypes (Envelope es a)))
            (endpoint, action)
            docOpts
    in api & apiEndpoints . traverse . response . respBody <>~
        createRespBodiesFor (Proxy :: Proxy es) (Proxy :: Proxy ctypes)

class CreateRespBodiesFor list ctypes where
  createRespBodiesFor
    :: Proxy list
    -> Proxy ctypes
    -> [(Text, MediaType, ByteString)]

instance CreateRespBodiesFor '[] ctypes where
  createRespBodiesFor
    :: Proxy '[]
    -> Proxy ctypes
    -> [(Text, MediaType, ByteString)]
  createRespBodiesFor Proxy Proxy = []

instance
       ( AllMimeRender ctypes (Envelope '[e] ())
       , CreateRespBodiesFor es ctypes
       , ToSample e
       )
    => CreateRespBodiesFor (e ': es) ctypes where
  createRespBodiesFor
    :: Proxy (e ': es)
    -> Proxy ctypes
    -> [(Text, MediaType, ByteString)]
  createRespBodiesFor Proxy ctypes =
    createRespBodyFor (Proxy :: Proxy e) ctypes <>
    createRespBodiesFor (Proxy :: Proxy es) ctypes

createRespBodyFor
  :: forall e ctypes.
     (AllMimeRender ctypes (Envelope '[e] ()), ToSample e)
  => Proxy e -> Proxy ctypes -> [(Text, MediaType, ByteString)]
createRespBodyFor Proxy ctypes = concatMap enc samples
    where
      samples :: [(Text, Envelope '[e] ())]
      samples = fmap toErrEnvelope <$> toSamples (Proxy :: Proxy e)

      enc :: (Text, Envelope '[e] ()) -> [(Text, MediaType, ByteString)]
      enc (t, s) = uncurry (t,,) <$> allMimeRender ctypes s

instance (HasDocs (Throwing (Snoc es e) :> api)) =>
    HasDocs (Throwing es :> Throws e :> api) where
  docsFor
    :: Proxy (Throwing es :> Throws e :> api)
    -> (Endpoint, Action)
    -> DocOptions
    -> API
  docsFor Proxy =
    docsFor (Proxy :: Proxy (Throwing (Snoc es e) :> api))

instance ToSample a => ToSample (Envelope es a) where
  toSamples :: Proxy (Envelope es a) -> [(Text, Envelope es a)]
  toSamples Proxy = fmap toSuccEnvelope <$> toSamples (Proxy :: Proxy a)
