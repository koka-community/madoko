/*---------------------------------------------------------------------------
  Copyright 2015 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Setting math options
module optionsMath

import std/os/path
import common
import options
import optionsSandbox


pub fun updateMath( options:options, key: string, lvalue: string, value:string, ivalue: int, bvalue:bool ) : options
{
  if (key=="mathjax-ext" || key=="mathjax-extension") then options(math = (options.math)(mjext=if (value=="") then "" else options.math.mjext ++ ";" ++ value))
  elif (key=="math-mode") then options.setMathMode(value)
  elif (key=="math-static" || key=="math-dir") then options(math = (options.math)(imgDir = if (lvalue=="true") then "math" else value))
  elif (key=="math-scale") then options(math = (options.math)(scale=ivalue))
  elif (key=="math-scale-svg") then options(math = (options.math)(scaleSvg=ivalue))
  elif (key=="math-scale-png") then options(math = (options.math)(scalePng=ivalue))
  elif (key=="math-baseline") then options(math = (options.math)(baseline=ivalue))
  elif (key=="math-dpi") then options(math = (options.math)(dpi=ivalue))
  elif (key=="math-embed" || key=="math-embed-limit") then options(math = (options.math)(embedLimit=if (value=="") then 0 elif (value=="true") then 1024 else (ivalue*1024)))
  elif (key=="math-document-class" || key=="math-doc-class") then options(math = (options.math)(docClass=value))
  elif (key=="math-render") then options(math = (options.math)(render = options.parseMathRender(lvalue,options.math.render)))
  elif (key=="math-render-full") then options(math = (options.math)(renderFull = options.parseMathRender(lvalue,options.math.renderFull ) ))
  elif (key=="math-svg-share-paths") then options(math = (options.math)(svgShare=bvalue))
  elif (key=="math-svg-precision") then options(math = (options.math)(svgPrec=min(6,max(ivalue,0))))
  elif (key=="math-svg-use-fonts") then options(math = (options.math)(svgFontFormat=if (bvalue) then "woff,ah" else "none"))
  elif (key=="math-svg-font-format") then options(math = (options.math)(svgFontFormat=lvalue))
  elif (key=="math-svg-bbox-exact") then options(math = (options.math)(svgBBoxExact=bvalue))
  elif (key=="mathjax") then (if (value!="")
                               then options(math = (options.math)(mode=Dynamic, mathjax=(if (lvalue=="true") then "default" else value)))
                               else options(math = (options.math)(mode=Static, mathjax="")))
  else {
    options.updateSandbox(key,lvalue,value,ivalue)
  }
}


fun setMathMode( options : options, value : string ) : options {
  val nvalue = value.normalizeId
  if (nvalue=="static") then options(math = (options.math)(mode=Static))
  elif (nvalue=="dynamic") then options(math = (options.math)(mode=Dynamic))
  elif (nvalue=="mathjax") then options(math = (options.math)(mode=Dynamic, mathjax=if (options.math.mathjax.bool) then options.math.mathjax else "default"))
  else {
    warning("unrecognized math mode: " ++ nvalue)
    options
  }
}

fun parseMathRender( options : options, value : string, def : maybe<mathrender> ) : maybe<mathrender> {
  if (value=="png") then Just(Png)
  elif (value=="svg") then Just(Svg)
  else {
    warning("unrecognized math rendering mode: " ++ value ++ ", expecting one of 'png' or 'svg'")
    def
  }
}
