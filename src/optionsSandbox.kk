/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Setting sandboxed options
module optionsSandbox

import std/os/path
import common
import options


pub fun updateSandbox( options : options, key : string, lvalue : string, value : string, ivalue : int ) : options
{
  // can only set program options if not running in a sandbox
  if (!(options.sandbox)) then  {
    if (key=="latex") then options(latex=if (value=="") then "latex" else value)
    elif (key=="dvipng") then options(math = (options.math)(dvipng=if (value=="") then "dvipng" else value))
    elif (key=="dvisvg") then options(math = (options.math)(dvisvg=if (value=="") then "dvisvgm" else value))
    elif (key=="pdflatex" || key=="pdf-latex") then options(pdflatex=if (lvalue=="true") then "default" else value)
    elif (key=="math-latex-full" || key=="math-pdflatex" || key=="math-pdf-latex") then options(math = (options.math)(latexFull=if (lvalue=="true") then "default" else value))
    elif (key=="math-latex") then options(math = (options.math)(latex=if (lvalue=="true") then "default" else value))
    elif (key=="math-concurrency") then options(math = (options.math)(concurrency=if (ivalue>=0 && ivalue<=256) then ivalue else options.math.concurrency))
    elif (key=="bibtex") then options(bibtex=value)
    elif (key=="convert") then options(math = (options.math)(convert=value))
    elif (key=="ps2pdf") then options(math = (options.math)(ps2pdf=value))
    elif (key=="dvips") then options(math = (options.math)(dvips=value))
    elif (key=="zip") then options(zip = value)
    elif (key=="process-timeout") then options(processTimeout=if (value!="" && ivalue > 0) then ivalue * 1000 else 0)
    else {
      options
    }
  }
  else {
    // in sandbox, only set safe program options
    if (key=="latex") then options(latex=if (value=="") then "latex" else safeLatex(lvalue, options.latex) )
    elif (key=="pdflatex" || key=="pdf-latex") then options(pdflatex=if (lvalue=="true") then "default" else safeLatex(lvalue, options.pdflatex) )
    elif (key=="math-latex-full" || key=="math-pdflatex" || key=="math-pdf-latex") then options(math = (options.math)(latexFull=if (lvalue=="true") then "default" else safeLatex(lvalue, options.math.latexFull) ))
    elif (key=="math-latex") then options(math = (options.math)(latex=if (lvalue=="true") then "default" else safeLatex(lvalue, options.math.latex) ))
    elif (key=="math-concurrency") then options(math = (options.math)(concurrency=if(ivalue >= 1 && ivalue <= 16) then ivalue else options.math.concurrency))
    elif (key=="bibtex") then options(bibtex=safeBibtex(lvalue,options.bibtex))
    else {
      //  if (options.verbose >= 3) warning("custom metadata key: " + key)
      options
    }
  }
}

fun safeLatex( s : string, def : string ) {
  if (s=="latex" || s=="xelatex" || s=="pdflatex")
   then s else def
}
fun safeBibtex( s : string, def : string ) {
  if (s=="bibtex" || s=="bibtex8")
   then s else def
}
