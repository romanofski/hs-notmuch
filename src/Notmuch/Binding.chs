-- Copyright (C) 2014, 2017  Fraser Tweedale
--
-- hs-notmuch is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE ForeignFunctionInterface #-}

module Notmuch.Binding where

import Control.Applicative ((<$>))
import Control.Monad

#include <notmuch.h>
{#context prefix = "notmuch" #}

import Foreign
import Foreign.C
import qualified System.IO.Unsafe

import qualified Data.ByteString as B

import Notmuch.Talloc


--
-- Type synonyms
--
type Tag = String
type MessageId = String
type ThreadId = String

--
-- BINDING API
--

{#enum status_t as Status {underscoreToCase} deriving (Eq) #}
{#enum database_mode_t as DatabaseMode {underscoreToCase} #}
{#enum sort_t as Sort {underscoreToCase} #}
{#enum message_flag_t as MessageFlag {underscoreToCase} #}
{#pointer *database_t as Database foreign newtype #}
{#pointer *query_t as Query foreign newtype #}
{#pointer *threads_t as Threads foreign newtype #}
{#pointer *thread_t as Thread foreign newtype #}
{#pointer *messages_t as Messages foreign newtype #}
{#pointer *message_t as Message foreign newtype #}
{#pointer *tags_t as Tags foreign newtype #}
{#pointer *directory_t as Directory foreign newtype #}
{#pointer *filenames_t as Filenames foreign newtype #}

instance Show Status where
  show a = System.IO.Unsafe.unsafePerformIO $
    {#call status_to_string #} (fromIntegral $ fromEnum a) >>= peekCString

-- | Open a Notmuch database
--
-- The database has no finaliser and will remain open even if GC'd.
--
database_open :: String -> IO (Either Status Database)
database_open s = withCString s $ \s' ->
  construct Database ({#call database_open #} s' 0) Nothing

-- notmuch_status_t notmuch_database_compact(path, backup_path, status_cb, closure)

database_get_path :: Database -> IO String
database_get_path db =
  withDatabase db {#call database_get_path #} >>= peekCString

database_get_version :: Database -> IO Int
database_get_version db =
  fromIntegral <$> withDatabase db {#call database_get_version #}

-- notmuch_database_needs_upgrade ## do automatically for updates
-- notmuch_database_upgrade ## do automatically for updates
-- notmuch_database_begin_atomic ## do automatically for updates
-- notmuch_database_end_atomic ## do automatically for updates

-- notmuch_database_get_directory

-- notmuch_database_add_message

-- notmuch_database_remove_message

database_find_message
  :: Database
  -> MessageId
  -> IO (Either Status (Maybe Message))
database_find_message db s =
  withDatabase db $ \db' ->
    withCString s $ \s' ->
      constructMaybe
        Message
        ({#call database_find_message #} db' s')
        message_destroy

database_find_message_by_filename
  :: Database -- ^ Database
  -> String   -- ^ Filename
  -> IO (Either Status (Maybe Message))
database_find_message_by_filename db s =
  withDatabase db $ \db' ->
    withCString s $ \s' ->
      constructMaybe
        Message
        ({#call database_find_message_by_filename #} db' s')
        message_destroy

-- TODO: check for NULL, indicating error
database_get_all_tags :: Database -> IO [Tag]
database_get_all_tags ptr = withDatabase ptr $ \ptr' ->
  {#call database_get_all_tags #} ptr'
    >>= detachPtr
    >>= newForeignPtr tags_destroy
    >>= tagsToList . Tags

-- TODO: check for NULL, indicating error
query_create :: Database -> String -> IO Query
query_create db s = withCString s $ \s' ->
  withDatabase db $ \db' ->
    {#call notmuch_query_create #} db' s'
      >>= detachPtr
      >>= fmap Query . newForeignPtr query_destroy

query_get_query_string :: Query -> IO String
query_get_query_string ptr =
  withQuery ptr ({#call query_get_query_string #} >=> peekCString)

query_set_sort :: Query -> Sort -> IO ()
query_set_sort ptr x = withQuery ptr $ \ptr' ->
  {#call query_set_sort #} ptr' (fromIntegral $ fromEnum x)

query_get_sort :: Query -> IO Sort
query_get_sort ptr = withQuery ptr $
  fmap (toEnum . fromIntegral) . {#call query_get_sort #}

query_add_tag_exclude :: Query -> Tag -> IO ()
query_add_tag_exclude ptr s =
  withQuery ptr $ \ptr' ->
    withCString s $ \s' ->
      {#call query_add_tag_exclude #} ptr' s'

query_search_threads :: Query -> IO [Thread]
query_search_threads ptr = withQuery ptr $ \ptr' ->
  {#call query_search_threads #} ptr'
     >>= detachPtr
     >>= newForeignPtr threads_destroy
     >>= threadsToList . Threads

query_search_messages :: Query -> IO [Message]
query_search_messages ptr = withQuery ptr $ \ptr' ->
  {#call query_search_messages #} ptr'
    >>= detachPtr
    >>= newForeignPtr messages_destroy
    >>= messagesToList . Messages

query_count_messages :: Query -> IO Int
query_count_messages query =
  fromIntegral <$> withQuery query {#call query_count_messages #}

query_count_threads :: Query -> IO Int
query_count_threads query =
  fromIntegral <$> withQuery query {#call query_count_threads #}

thread_get_thread_id :: Thread -> IO ThreadId
thread_get_thread_id ptr =
  withThread ptr ({#call thread_get_thread_id #} >=> peekCString)

-- notmuch_thread_get_total_messages
-- notmuch_thread_get_toplevel_messages -> Messages

thread_get_messages :: Thread -> IO [Message]
thread_get_messages ptr = withThread ptr $ \ptr' ->
  {#call thread_get_messages #} ptr'
    >>= detachPtr
    >>= newForeignPtr messages_destroy
    >>= messagesToList . Messages

-- notmuch_thread_get_matched_messages -> Int
-- notmuch_thread_get_authors -> String
-- notmuch_thread_get_subject
-- notmuch_thread_get_oldest_date
-- notmuch_thread_get_newest_date

thread_get_tags :: Thread -> IO [Tag]
thread_get_tags ptr = withThread ptr $ \ptr' ->
  {#call thread_get_tags #} ptr'
    >>= detachPtr
    >>= newForeignPtr tags_destroy
    >>= tagsToList . Tags

messages_collect_tags :: Messages -> IO [Tag]
messages_collect_tags ptr = withMessages ptr $ \ptr' ->
  {#call messages_collect_tags #} ptr'
    >>= detachPtr
    >>= newForeignPtr tags_destroy
    >>= tagsToList . Tags

message_get_message_id :: Message -> IO String
message_get_message_id ptr =
  withMessage ptr ({#call message_get_message_id #} >=> peekCString)

message_get_thread_id :: Message -> IO ThreadId
message_get_thread_id ptr =
  withMessage ptr ({#call message_get_thread_id #} >=> peekCString)

message_get_replies :: Message -> IO [Message]
message_get_replies ptr = withMessage ptr $ \ptr' ->
  {#call message_get_replies #} ptr'
    >>= detachPtr
    >>= newForeignPtr messages_destroy
    >>= messagesToList . Messages

message_get_filename :: Message -> IO String
message_get_filename ptr =
  withMessage ptr ({#call message_get_filename #} >=> peekCString)

message_get_flag :: Message -> MessageFlag -> IO Bool
message_get_flag ptr flag = withMessage ptr $ \ptr' -> do
  result <- {#call message_get_flag #} ptr' (enumToCInt flag)
  return $ result /= 0

-- DB NEEDS TO BE WRITABLE???
message_set_flag :: Message -> MessageFlag -> Bool -> IO ()
message_set_flag ptr flag v = withMessage ptr $ \ptr' ->
  {#call message_set_flag #} ptr' (enumToCInt flag) (enumToCInt v)

message_get_date :: Message -> IO CLong
message_get_date = flip withMessage {#call message_get_date #}

-- returns EMPTY STRING on missing header,
-- NOTHING on error (I know, confusing)
--
-- possible optimisation: detachPtr the returned string and
-- B.unsafePackCStringFinalizer to turn it into a ByteString
-- with talloc_free finaliser.  This will be O(n) because
-- must use strlen(3) to learn string length, and avoids
-- malloc.  Measure carefully to see if this would be worth it,
-- because it couples to both notmuch internals and unstable
-- parts of bytestring API (Data.ByteString.Unsafe).
--
message_get_header :: Message -> B.ByteString -> IO (Maybe B.ByteString)
message_get_header ptr s =
  B.useAsCString s $ \s' ->
    withMessage ptr $ \ptr' -> do
      r <- {#call message_get_header #} ptr' s'
      if r == nullPtr
        then pure Nothing
        else Just <$> B.packCString r

message_get_tags :: Message -> IO [Tag]
message_get_tags ptr = withMessage ptr $ \ptr' ->
  {#call message_get_tags #} ptr'
    >>= detachPtr
    >>= newForeignPtr tags_destroy
    >>= tagsToList . Tags

-- message_add_tag
-- message_remove_tag
-- message_remove_all_tags
-- message_maildir_flags_to_tags
-- message_tags_to_maildir_flags
-- message_freeze
-- message_thaw

-- directory functions

-- filenames functions

--
-- Destructors
--

foreign import ccall "&notmuch_database_destroy"
  database_destroy :: FinalizerPtr a

foreign import ccall "&notmuch_query_destroy"
  query_destroy :: FinalizerPtr a

foreign import ccall "&notmuch_threads_destroy"
  threads_destroy :: FinalizerPtr a

foreign import ccall "&notmuch_thread_destroy"
  thread_destroy :: FinalizerPtr a

foreign import ccall "&notmuch_messages_destroy"
  messages_destroy :: FinalizerPtr a

foreign import ccall "&notmuch_message_destroy"
  message_destroy :: FinalizerPtr a

foreign import ccall "&notmuch_tags_destroy"
  tags_destroy :: FinalizerPtr a


--
-- UTILITY FUNCTIONS
--

enumToCInt :: Enum a => a -> CInt
enumToCInt = fromIntegral . fromEnum

-- | Receive an object into a pointer, handling nonzero status.
--
construct
  :: (ForeignPtr p -> p)
  -- ^ Haskell data constructor
  -> (Ptr (Ptr p) -> IO CInt)
  -- ^ C double-pointer-style constructor
  -> Maybe (FinalizerPtr p)
  -- ^ Optional destructor
  -> IO (Either Status p)
construct dcon constructor destructor =
  let f = maybe newForeignPtr_ newForeignPtr destructor
  in alloca $ \ptr -> do
    status <- (toEnum . fromIntegral) <$> constructor ptr
    if status == StatusSuccess
      then fmap (Right . dcon) $ f =<< peek ptr
      else return $ Left status

-- | Receive an object into a pointer, handling nonzero status and null.
--
constructMaybe
  :: (ForeignPtr p -> p)
  -- ^ Haskell data constructor
  -> (Ptr (Ptr p) -> IO CInt)
  -- ^ C double-pointer-style constructor
  -> FinalizerPtr p
  -- ^ Destructor function pointer
  -> IO (Either Status (Maybe p))
constructMaybe dcon constructor destructor =
  alloca $ \ptr -> do
    status <- constructor ptr
    if status /= 0
      then return $ Left $ toEnum $ fromIntegral status
      else fmap Right $ peek ptr >>= \ptr' -> if ptr' /= nullPtr
        then Just . dcon <$> newForeignPtr destructor ptr'
        else return Nothing

-- | Turn a C iterator into a list
--
ptrToList
  :: (p -> (Ptr p -> IO [b]) -> IO [b])
  -- ^ Pointer unwrapper function (e.g. `withMessages`)
  -> (Ptr p -> IO (CInt))
  -- ^ Predicate on iterator
  -> (Ptr p -> IO a)
  -- ^ Iterater getter function
  -> (Ptr p -> IO ())
  -- ^ Function to advance iterator
  -> (a -> IO b)
  -- ^ Item mapper
  -> p
  -- ^ Pointer
  -> IO [b]
ptrToList withFObj test get next f fObj = withFObj fObj ptrToList'
  where
  ptrToList' ptr = test ptr >>= \valid -> if valid == 0
    then return []
    else liftM2 (:)
      (get ptr >>= f >>= \x -> next ptr >> pure x)
      (ptrToList' ptr)

tagsToList :: Tags -> IO [String]
tagsToList = ptrToList
  withTags
  {#call tags_valid #}
  {#call tags_get #}
  {#call tags_move_to_next #}
  peekCString

threadsToList :: Threads -> IO [Thread]
threadsToList = ptrToList
  withThreads
  {#call threads_valid #}
  {#call threads_get #}
  {#call threads_move_to_next #}
  (fmap Thread . newForeignPtr thread_destroy <=< detachPtr)

messagesToList :: Messages -> IO [Message]
messagesToList = ptrToList
  withMessages
  {#call messages_valid #}
  {#call messages_get #}
  {#call messages_move_to_next #}
  (fmap Message . newForeignPtr message_destroy <=< detachPtr)
