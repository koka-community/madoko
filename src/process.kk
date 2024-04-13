/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/
module process

import std/os/path
import std/data/dict

extern import {
  cs file "process-inline.cs"
  js file "process-inline.js"
}

extern import {
  js child "child_process"
}

// quote file and command names for shell execution
pub fun quote( s : string ) : string {
  "\"" ++ s ++ "\""
}

pub fun system( cmd : string, callback : (int,string,string) -> <io|e> (), timeout : int = 0, cwd : string = "", env : list<(string,string)> = []) : <io|e> () {
  systemx(cmd,callback,timeout,cwd,if (env.isNil) then Nothing else Just(dict(env)))
}

extern systemx( cmd : string, callback : (int,string,string) -> <io|e> (), timeout : int = 0, cwd : string = "", env : maybe<dict<string>> = Nothing ) : <io|e> () {
  cs inline "ShellCommand.system(#1,#2,#3,#4)" // TODO: environment
  js inline "system_exec(#1,#2,#3,#4,#5)"
}
