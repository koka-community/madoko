/*---------------------------------------------------------------------------
  Copyright 2015 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/
module runcsl

import std/os/path
import texParser

extern import {
  js csl "./csl-madoko"
}


pub struct fileinfo( 
  filename: string,
  contents: string
)

pub struct citeinfo(
  id: string,
  lineinfo: string
)

pub struct cslresult(
  bibliography: string,
  bib         : string,
  warnings    : string,
  errors      : string,
  citeformat  : string
)


pub fun runCsl( 
  citations : list<citeinfo>, bibs : list<fileinfo>, bibstyle : fileinfo, 
  madokoStyle : fileinfo, localeStyle : fileinfo, id : string, attrs0 : string ) : cslresult 
{
  val preid = if (id.bool) then id + ":" else ""
  val attrs = "data-style:'" + bibstyle.filename.stemname + "'; " + attrs0
  makeBiblX( citations.unlist, 
              bibs.unlist, bibstyle, madokoStyle, localeStyle, 
              fn(tex) { parseTex(tex) }, preid, attrs )  
}

extern makeBiblX( citations : primarray<citeinfo>, bibtexs: primarray<fileinfo>, 
                    bibstyle : fileinfo, 
                    madokoStyle : fileinfo, localeStyle : fileinfo,
                    convertTex : (string) -> string,
                    pre: string, attrs : string ) : cslresult
{
  js inline "csl.makeBibliography(#1,#2,#3,#4,#5,#6, {preid:#7,attrs:#8})"
}
