import macros, tables, unicode
import pixwindy, pixie, fusion/matching, fusion/astdsl
import render
export pixwindy, pixie, render

{.experimental: "caseStmtMacros".}

var
  boxStack*: seq[Rect]

template frameImpl(fbox: Rect; clip: bool; body) =
  # todo: clip
  bind boxStack
  bind bound
  block:
    var box {.inject.}: Rect
    if boxStack.len == 0:
      box = fbox
      boxStack.add box
    else:
      box = fbox
      box.xy = box.xy + boxStack[^1].xy
      boxStack.add box

    block: body

    boxStack.del boxStack.high

template parentBox*: Rect =
  bind boxStack
  boxStack[^1]


proc makeFrame(args: seq[NimNode]): NimNode =
  let body = args[^1]
  let a = block:
    var r: seq[(string, NimNode)]
    for it in args[0..^2]:
      case it
      of ExprEqExpr[Ident(strVal: @s), @b]:
        r.add (s, b)
      of Asgn[Ident(strVal: @s), @b]:
        r.add (s, b)
      else: error("unexpected syntax", it)
    r
  let d = a.toTable

  # checks
  if "wh" in d and ("w" in d or "h" in d): error("duplicated property", d["wh"][1])
  if "xy" in d and ("x" in d or "y" in d): error("duplicated property", d["xy"][1])
  if ("centerIn" in d) and ("xy" in d or "x" in d or "y" in d): error("duplicated property", d["xy"][1])

  buildAst: blockStmt empty(), stmtList do:
    if "wh" in d:
      letSection: identDefs:
        ident"wh"
        empty()
        call ident"vec2", d["wh"]
    else:
      letSection: identDefs:
        ident"wh"
        empty()
        call ident"vec2":
          call ident"float32":
            if "w" in d: d["w"]
            else:        dotExpr(call(bindSym"parentBox"), ident"w")
          call ident"float32": 
            if "h" in d: d["h"]
            else:        dotExpr(call(bindSym"parentBox"), ident"h")

    if "centerIn" in d:
      letSection: identDefs:
        ident"xy"
        empty()
        infix ident"+":
          dotExpr(call(bindSym"parentBox", ident"xy"))
          infix ident"-":
            infix ident"/", dotExpr(call(bindSym"parentBox"), ident"wh"), newLit 2
            infix ident"/", ident"wh", newLit 2

    else:
      if "xy" in d:
        letSection: identDefs:
          ident"xy"
          empty()
          call ident"vec2", d["xy"]
      else:
        letSection: identDefs:
          ident"xy"
          empty()
          call ident"vec2":
            call ident"float32": 
              if "x" in d: d["x"]
              else:        newLit 0
            call ident"float32": 
              if "y" in d: d["y"]
              else:        newLit 0

    call bindSym"frameImpl":
      call bindSym"rect", ident"xy", ident"wh"
      if "clip" in d: d["clip"]
      else:           newLit false
      body


macro frame*(args: varargs[untyped]) =
  runnableExamples:
    frame(center in parentBox, w=100, h=50, clip=true):
      frame(x=10, wh=vec2(10, 10)):
        frame(center=boxStack[^2].xy, wh=vec2(20, 20)):
          ## ...

  makeFrame(args[0..^1])


macro component*(name, body: untyped) =
  var noexport: bool
  var name = name
  case name
  of PragmaExpr[@ni is Ident(), Pragma[Ident(strVal: "noexport")]]:
    name = ni
    noexport = true
  else: discard

  proc isTypename(x: NimNode): bool =
    x.kind == nnkIdent and x.strVal.runeAt(0).isUpper

  proc impl(x: NimNode): NimNode =
    proc handleComponent(name: NimNode, args: seq[NimNode], firstArg: NimNode): NimNode =
      var body1: seq[NimNode]
      var body2: seq[NimNode]
      var d: Table[string, NimNode]
      var fd: seq[NimNode]
      var lasteq: int
      for i, a in args:
        if a.kind in {nnkExprEqExpr, nnkAsgn} and a[0].kind == nnkIdent:
          lasteq = i
      for i, a in args:
        if a.kind in {nnkExprEqExpr, nnkAsgn} and a[0].kind == nnkIdent:
          let s = a[0].strVal
          case s
          of "w", "h", "wh", "x", "y", "xy", "clip":
            fd.add a
          else:
            if s in d: error("duplicated property", a[0])
            d[s] = a[1]
        else:
          if i > lasteq:
            body2.add a
          else:
            body1.add a

      buildAst blockStmt:
        empty()
        stmtList:
          for x in body1: impl(x)

          let b = buildAst call:
            ident"handle"
            name
            if firstArg != nil: firstArg
            for k, v in d:
              exprEqExpr:
                ident k
                v

          if fd.len != 0:
            makeFrame(fd & b)
          else: b

          for x in body2: impl(x)

    case x
    # T: d=e and T(b=c): d=e
    of Call[@name is Ident(isTypename: true), @arg, all @args]:
      if args.len == 0 and arg.kind == nnkStmtList:
        handleComponent name, arg[0..^1], nil
      elif args.len != 0 and args[^1].kind == nnkStmtList:
        handleComponent name, arg & args[0..^2] & args[^1][0..^1], nil
      else:
        x

    # T a(b=c)
    of Command[@name is Ident(isTypename: true), Call[@arg, all @args]]:
      handleComponent name, args, arg

    # T a(b=c): d=e
    of Command[@name is Ident(isTypename: true), Call[@arg, all @args], @args2 is StmtList()]:
      handleComponent name, args & args2[0..^1], arg

    elif x.len > 0:
      var y = x
      for i in 0..<y.len: y[i] = impl(y[i])
      y

    else: x

  buildAst stmtList:
    if noexport:
      quote do:
        when not compiles(`name`):
          type `name` = object
    else:
      quote do:
        when not compiles(`name`):
          type `name`* = object

    var body = body[0..^1]

    procDef:
      if noexport: ident"handle"
      else: postfix:
        ident"*"
        ident"handle"
      empty()
      empty()
      formalParams:
        empty()
        identDefs:
          gensym(nskParam)
          bracketExpr(ident"typedesc", name)
          empty()
        if body.len != 0 and body[0].kind == nnkProcDef and body[0][0] == ident"handle":
          for x in body[0].params[1..^1]: x
          body = body[1..^1]
      empty()
      empty()
      stmtList:
        for x in body: impl(x)
