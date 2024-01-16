/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Options from metadata
module optionsMeta

import std/os/path
import common
import options
import optionsSandbox
import optionsMath

extern import {
  js locs "./locales"
}

extern normalizeLocale( lang : string ) : string {
  js inline "locs.getLocaleInfo(#1).langid"
}

pub fun fromMeta( opts : options, mdata : metadata ) : options {
  //opts = opts0(metadata = opts0.metadata + mdata)
  mdata.foldl(opts) fn(options : options, kv : (string,string)) {
    val (key,xvalue) = kv
    options.update( key, xvalue, mdata )
  }
}

fun update( options : options, key : string, xvalue : string, mdata : metadata ) : options {  
  val lvalue = xvalue.toLower
  val value  = if (lvalue=="none" || lvalue=="clear" || lvalue=="false") then "" else xvalue
  val ivalue = value.parseInt.maybe(~1,id)
  val bvalue = (value!="" && value!="0") 

  //trace("from meta: " + key + "=" + value)
  if   (key=="title") then options(title=value)
  elif (key=="prelude") then options(prelude=value)
  elif (key=="css") then options(css=if (value=="") then "" else options.css + ";" + value)
  elif (key=="html-meta") then options(htmlMeta=if (value=="") then "" else options.htmlMeta + ";" + value)
  elif (key=="script") then options(scripts=if (value=="") then "" else options.scripts + ";" + value)
  elif (key=="script-") then options(scriptsx=if (value=="") then "" else options.scriptsx + ";" + value)
  elif (key=="package") then options(packages=if (value=="") then "" else options.packages + ";" + value)
  elif (key=="package-") then options(packagesx=if (value=="") then "" else options.packagesx + ";" + value)
  elif (key=="toc-depth" && ivalue >= 0) then options(tocDepth = ivalue)
  elif ((key=="heading-depth" || key=="header-depth") && ivalue >= 0) then options(headingDepth = ivalue)
  elif ((key=="heading-base" || key=="header-base" || key=="base-header-level") && ivalue >= 0) then options(headingBase = ivalue)
  elif (key=="document-class" || key=="doc-class") then options(docClass=value)
  //elif (key=="bib" || key=="bibliography" || key=="bib-data") options(bib=if (value=="") then "" else options.bib + ";" + value)
  elif (key=="bib" || key=="bibliography" || key=="bib-data") then {
    if (value!="") then log("files", value.changeExt(".bib"))
    options(bib=if (value=="") then "" else options.bib + ";" + value);
  }
  elif (key=="bib-style" || key=="biblio-style" || key=="bibliography-style") then {
    if (value.extname!="" || value.dirname!="") then { // we need to log here since we don't always 'read' the bst if the bibs are unchanged
      log("files", value.defaultExt(".bst"))
    }
    if (value.bool) then options(bibStyle=Bst(value,"")) else options
  }
  elif (key=="csl-style") then { 
    val cslname = if (value.extname.isEmpty && value.dirname.isEmpty) 
                   then lvalue.replaceAll(" ","-") // normalize CSL style name
                   else value
    // we need to log here since we don't always 'read' the cls if the bibs are unchanged
    if (cslname.bool) then {
      //log("files", cslname.defaultExt(".csl"))
      //log("files", "madoko.csl")
      //log("files", "locales-en-US.xml")
      options(bibStyle=Csl(cslname,"")) 
    }
    else options
  }
  elif (key=="locale") then { options(locale=normalizeLocale(value)) }  
  elif (key=="html-header") then options(htmlHeader=if(value=="") then "" else options.htmlHeader.appendNL(value))
  elif (key=="css-header") then options(cssHeader=if(value=="") then "" else options.cssHeader.appendNL(value))
  elif (key=="html-footer") then options(htmlFooter=if(value=="") then "" else options.htmlFooter.appendNL(value))
  elif (key=="js-header") then options(jsHeader=if(value=="") then "" else options.jsHeader.appendNL(value))
  elif (key=="js-footer") then options(jsFooter=if(value=="") then "" else options.jsFooter.appendNL(value))
  elif (key=="tex-header") then options(texHeader =if(value=="") then "" else options.texHeader.appendNL(value))
  elif (key=="tex-header-") then options(texHeaderx =if(value=="") then "" else options.texHeaderx.appendNL(value))
  elif (key=="tex-doc-header") then options(texDocHeader =if(value=="") then "" else options.texDocHeader.appendNL(value))
  elif (key=="tex-doc-header-") then options(texDocHeaderx =if(value=="") then "" else options.texDocHeaderx.appendNL(value))
  elif (key=="tex-footer") then options(texFooter =if(value=="") then "" else options.texFooter.appendNL(value))
  elif (key=="tex-section-num") then options(texSectionNum=(value!=""))
  elif (key=="fragment-start" || key=="extract-start") then options(extractStart=xvalue)
  elif (key=="fragment-end" || key=="extract-end") then options(extractEnd=xvalue)
  
  elif (key=="cite-style") then {
    if (lvalue=="clear" || lvalue=="none") then options(citestyle = Nothing)
    elif (lvalue=="") then options
    else match(parseCiteStyle(lvalue)) {
      Nothing -> {
        warning("unrecognized citation style: " + lvalue)
        options
      }
      Just(cs) -> options(citestyle=Just(cs))
    }      
  }
  elif (key=="cite-all") then options(citeAll=(value!="")) 
  elif (key=="embed" || key=="embed-limit") then options(embedLimit=if (value=="") then 0 elif (value=="true") then 1024 else (ivalue*1024))
  elif (key=="section-depth") then options(sectionMax=ivalue)
  elif (key=="section-base") then options(sectionBase=ivalue)
  elif (key=="highlight" || key=="colorize") then options(highlight=if (value=="") then False else True)
  elif (key=="highlight-language" || key=="colorizer") then options(hilitelang=if (value=="") then "" else options.hilitelang + ";" + value)
  elif (key=="rebuild") then options(rebuild=(value != ""))
  elif (key=="star-bold") then options(starBold=(value!=""))
  elif (key=="line-no") then options(lineNo=ivalue)
  elif (key=="line-no-web") then options(lineNoWeb = (lvalue=="true"))
  elif (key=="pretty-align") then options(prettyAlign=ivalue)
  elif (key=="logo") then options(logo=(lvalue=="true"))
  elif (key=="refer") then { log("filesRefer",value); options }
  elif (key=="copy-styles") then options(copyStyles=(value!=""))
  elif (key.startsWith("math")) then {
    options.updateMath( key, lvalue, value, ivalue, bvalue )
  }
  else {
    options.updateSandbox( key, lvalue, value, ivalue )
  }
}


fun appendNL(s : string, t : string ) : string {
  if (s == "" || s.endsWith("\n")) then s + t else s + "\n" + t
}


fun appendValue( xs : list<string>, x : string, sep : string = "&br;" ) : list<string> {
  match(xs.reverse) {
    Nil -> [x]
    Cons(y,yy) -> if (y=="") then Cons(x,yy).reverse else Cons(y + sep + x,yy).reverse
  }
}