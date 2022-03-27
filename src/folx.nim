import sequtils, os, times, math, unicode, std/monotimes, options
import pixwindy, pixie, cligen
import render, syntax_highlighting, configuration, text_editor, side_explorer, git

proc contains*(b: Rect, a: GVec2): bool =
  let a = a.vec2
  a.x >= b.x and a.x <= b.x + b.w and a.y >= b.y and a.y <= b.y + b.h


proc status_bar(
  r: Context,
  box: Rect,
  gt: var GlyphTable,
  bg: ColorRgb,
  fields: seq[tuple[field: string, value: string]],
  ) =

  const margin = vec2(8, 2)
  var s = ""

  for i in fields:
    s.add(i.field & ": " & i.value & "   ")
  
  r.fillStyle = bg
  r.fillRect box

  r.image.draw toRunes(s), sText.color, box.xy + margin, rect(box.xy, box.wh - margin), gt, bg


proc folx(files: seq[string] = @[], workspace: string = "", args: seq[string]) =
  let files =
    if files.len != 0 or (args.len != 0 and not args.any(dirExists)): files & args
    elif files.len != 0: files
    else: @[config.file]
  
  let workspace = absolutePath:
    if workspace != "": workspace
    elif args.len != 0 and args[0].dirExists: args[0]
    elif files.len == 0 or files == @[config.file]: config.workspace
    else: files[0].splitPath.head
  
  let window = newWindow("folx", config.window.size, visible=false)
  window.runeInputEnabled = true

  var
    editor_gt    = readFont(config.font).newGlyphTable(config.fontSize)
    interface_gt = readFont(config.interfaceFont).newGlyphTable(config.interfaceFontSize)

    text_editor: TextEditor

    displayRequest = false
    image = newImage(1280, 720)
    r = image.newContext

    # for explorer
    pos = 0.0'f32

  var main_explorer = SideExplorer(current_dir: workspace, item_index: 1, display: false, pos: 0)

  proc open_file(file: string) =
    window.title = file & " - folx"
    text_editor = newTextEditor(file)

  open_file files[0]

  proc animate(dt: float32): bool =
    # todo: refactor repeat code
    if main_explorer.display:
      if pos != main_explorer.pos:
        let
          fontSize = editor_gt.font.size
          pvp = (main_explorer.pos * fontSize).round.int32  # visual position in pixels
          
          # position delta
          d = (abs(pos - main_explorer.pos) * pow(1 / 2, (1 / dt) / 50)).max(0.1).min(abs(pos - main_explorer.pos))

        # move position by delta
        if pos > main_explorer.pos: main_explorer.pos += d
        else:                main_explorer.pos -= d

        # if position close to integer number, round it
        if abs(main_explorer.pos - pos) < 1 / fontSize / 2.1:
          main_explorer.pos = pos
        
        # if position changed, signal to display by setting result to true
        if pvp != (main_explorer.pos * fontSize).round.int32: result = true
    
    result = result or text_editor.animate(
      dt = dt,
      gt = editor_gt
    )


  proc display =
    image.clear colorTheme.textarea.color.rgbx

    if main_explorer.display:

      var box = rect(vec2(0, 0), vec2(200, window.size.vec2.y))
      var dy = round(editor_gt.font.size * 1.27)
      var y = box.y - dy * (pos mod 1)

      r.image.draw toRunes(main_explorer.dir.path), sKeyword.color, vec2(box.x, y), box, editor_gt, configuration.colorTheme.textarea
      y += dy

      r.side_explorer_area(
        image = image,
        box = box,
        pos = main_explorer.pos,
        gt = editor_gt,
        bg = configuration.colorTheme.textarea,
        dir = main_explorer.dir,
        explorer = main_explorer,
        count_items = 0,
        y = y,
        nesting = 0,
      )

      r.text_editor(
        box = rect(vec2(box.w, 0), window.size.vec2 - vec2(box.w, 20)),
        gt = editor_gt,
        bg = colorTheme.textarea,
        editor = text_editor,
      )

      r.status_bar(
        box = rect(vec2(0, window.size.vec2.y - 20), vec2(window.size.vec2.x, 20)),
        gt = interface_gt,
        bg = colorTheme.statusBarBg,
        fields = @[
          ("count_items", $main_explorer.count_items),
          ("item", $main_explorer.item_index),
        ] & (
          if main_explorer.current_dir.gitBranch.isSome: @[
            ("git", main_explorer.current_dir.gitBranch.get),
          ] else: @[]
        ) & @[
          ("visual_pos", $main_explorer.pos),  
        ]
      )
    else:  
      r.text_editor(
        box = rect(vec2(0, 0), window.size.vec2 - vec2(0, 20)),
        gt = editor_gt,
        bg = colorTheme.textarea,
        editor = text_editor,
      )

      r.status_bar(
        box = rect(vec2(0, window.size.vec2.y - 20), vec2(window.size.vec2.x, 20)),
        gt = interface_gt,
        bg = colorTheme.statusBarBg,
        fields = @[
          ("line", $text_editor.cursor[1]),
          ("col", $text_editor.cursor[0]),
        ] & (
          if main_explorer.current_dir.gitBranch.isSome: @[
            ("git", main_explorer.current_dir.gitBranch.get),
          ] else: @[]
        ) & @[
          ("visual_pos", $text_editor.visual_pos),  
        ]
      )

    window.draw image



  window.onCloseRequest = proc =
    close window
    quit(0)


  window.onScroll = proc =
    if window.scrollDelta.y == 0: return
    if window.buttonDown[KeyLeftControl] or window.buttonDown[KeyRightControl]:
      let newSize = (editor_gt.font.size * (pow(17 / 16, window.scrollDelta.y))).round.max(1)
      
      if editor_gt.font.size != newSize:
        editor_gt.font.size = newSize
      else:
        editor_gt.font.size = (editor_gt.font.size + window.scrollDelta.y).max(1)
      
      clear editor_gt
      displayRequest = true
    else:
      if main_explorer.display:
        if window.mousePos in rect(vec2(0, 0), vec2(200, window.size.vec2.y)):
          let lines_count = main_explorer.count_items.float32
          pos = (pos - window.scrollDelta.y * 3).max(0).min(lines_count)
        
        else:
          text_editor.onScroll(
            delta = window.scrollDelta,
          )
      
      else:
        text_editor.onScroll(
          delta = window.scrollDelta,
        )


  window.onResize = proc =
    if window.size.x * window.size.y == 0: return
    image = newImage(window.size.x, window.size.y)
    r = image.newContext
    display()

  window.onButtonPress = proc(button: Button) =
    if window.buttonDown[KeyLeftControl] and button == KeyE:
      main_explorer.display = not main_explorer.display
      
      if main_explorer.display:
        pos = main_explorer.pos
        main_explorer.updateDir config.file

    elif main_explorer.display:
      side_explorer_onButtonDown(
        button = button,
        explorer = main_explorer,
        path = config.file,
        onFileOpen = (proc(file: string) =
          open_file file
        ),
      )

    else:
      text_editor.onButtonDown(
        button = button,
        window = window,
        onTextChange = (proc = discard),
      )
    
    display()

  window.onRune = proc(rune: Rune) =
    if not main_explorer.display:
      text_editor.onRuneInput(
        rune = rune,
        onTextChange = (proc =
          display()
        )
      )

  display()
  window.visible = true

  var pt = getMonoTime()  # main clock
  while not window.closeRequested:
    let nt = getMonoTime()  # tick start time
    pollEvents()
    
    let dt = getMonoTime()
    # animate
    displayRequest = displayRequest or animate((dt - pt).inMicroseconds.int / 1_000_000)

    if displayRequest:
      display()
      displayRequest = false
    
    pt = dt  # update main clock

    # sleep when no events happen
    let ct = getMonoTime()
    if (ct - nt).inMilliseconds < 10:
      sleep(10 - (ct - nt).inMilliseconds.int)

dispatch folx
