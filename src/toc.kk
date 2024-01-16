/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Documentation for the Madoko program sources.

module toc

import std/os/flags
import std/text/regex
import std/os/path
import std/os/file
import std/os/env

import common
import entity
import attributes
import options
import block
import inline
import texParser
import texFormatter
import htmlFormatter
import formatInline
import formatBlock
import definitions
import madoko
import main
