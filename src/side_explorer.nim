import std/sequtils, os, std/unicode, math, strutils, std/algorithm
import pixwindy, pixie
import render, configuration

type 
  File* = object
    path*: string
    dir*: string
    name*: string
    ext*: string
    open*: bool
    files*: seq[File]
    info*: FileInfo
  
  OpenDir* = object
    path*: string
  
  SideExplorer* = object
    current_dir*: string
    current_item*: PathComponent
    current_item_name*: string
    current_item_path*: string
    current_item_ext*: string
    count_items*: int
    pos*: float32
    item_index*: int
    dir*: File
    display*: bool
    open_dirs*: seq[OpenDir]
    new_dir_item_index*: bool 

proc nameUpCmp*(x, y: File): int =
  if x.name & x.ext >= y.name & y.ext: 1
  else: -1

proc folderUpCmp*(x, y: File): int =
  if (x.info.kind, y.info.kind) == (PathComponent.pcFile, PathComponent.pcDir): 1
  else: -1

proc folderDownCmp*(x, y: File): int =
  if (x.info.kind, y.info.kind) == (PathComponent.pcDir, PathComponent.pcFile): 1
  else: -1

proc bySizeUpCmp*(x, y: File): int =
  if x.info.size < y.info.size: 1
  else: -1

proc bySizeDownCmp*(x, y: File): int =
  if x.info.size > y.info.size: 1
  else: -1


let i_folder = readImage rc"icons/folder.svg"
let i_openfolder = readImage rc"icons/openfolder.svg"
let i_nim = readImage rc"icons/nim.svg"
let i_file = readImage rc"icons/file.svg"
let i_gitignore = readImage rc"icons/gitignore.svg"

proc getIcon(explorer: SideExplorer, file: File): Image =
  if OpenDir(path: file.path / file.name & file.ext) in explorer.open_dirs:
    result = i_openfolder
  else:
    result = i_folder

proc getIcon(file: File): Image =
  case file.ext
  of ".nim": result = i_nim
  else: 
    case file.name
    of ".gitignore": result = i_gitignore
    else: result = i_file


proc newFiles(file_path: string): seq[File] =
  var info: FileInfo
  var files: seq[File] = @[]
  
  for file in walkDir(file_path):
    try:
      let (dir, name, ext) = splitFile(file.path)
      info = getFileInfo(file.path)

      var new_file = File(
        path: file_path,
        dir: dir,
        name: name,
        ext: ext,
        open: false,
        files: @[],
        info: info
      )
      files.add(new_file)
    except:
      discard

  return files


proc updateDir*(explorer: var SideExplorer, path: string) =
  let (dir, name, ext) = splitFile(explorer.current_dir)
  let info = getFileInfo(explorer.current_dir)
  explorer.dir = File(
    path: explorer.current_dir,
    dir: dir,
    name: name,
    ext: ext,
    open: false,
    files: newFiles(explorer.current_dir),
    info: info,
  )

proc onButtonDown*(
  explorer: var SideExplorer,
  button: Button,
  path: string,
  onFileOpen: proc(file: string)
  ) =
  case button
  
  of KeyLeft:
    if explorer.current_item == PathComponent.pcDir:
      explorer.open_dirs = explorer.open_dirs.filterIt(it != OpenDir(path: explorer.current_item_path / explorer.current_item_name))
    
  of KeyUp:
    if explorer.item_index > 1:
      dec explorer.item_index
  
  of KeyDown:
    if explorer.item_index < explorer.count_items:
      inc explorer.item_index

  of KeyRight:
    if explorer.current_item == PathComponent.pcFile:
      onFileOpen(explorer.current_item_path / explorer.current_item_name & explorer.current_item_ext)
    elif explorer.current_item == PathComponent.pcDir:
      explorer.open_dirs.add(OpenDir(path: explorer.current_item_path / explorer.current_item_name & explorer.current_item_ext))

  else: discard


proc updateExplorer(explorer: var SideExplorer, file: File) =
  explorer.current_item = file.info.kind
  explorer.current_item_path = file.path
  explorer.current_item_name = file.name
  explorer.current_item_ext = file.ext

proc drawDir(
  explorer: var SideExplorer,
  image: Image,
  file: File,
  r: Context,
  box: Rect,
  nesting_indent: string,
  text: string,
  gt: var GlyphTable,
  bg: ColorRgb,
  y: var float32,
  dy: float32,
  icon_const: float32
  ) =

  image.draw(getIcon(explorer, file), translate(vec2(box.x + 20 + nesting_indent.toRunes.width(gt).float32, y + 4)) * scale(vec2(icon_const * dy, icon_const * dy)))
  r.image.draw text.toRunes, colorTheme.cActive, vec2(box.x + 40, y), box, gt, bg
  y += dy


proc drawSelectedDir(
  explorer: var SideExplorer,
  image: Image,
  file: File,
  r: Context,
  box: Rect,
  nesting_indent: string,
  text: string,
  gt: var GlyphTable,
  y: var float32,
  dy: float32,
  icon_const: float32
  ) =

  updateExplorer(explorer, file)

  r.fillStyle = colorTheme.bgSelection
  r.fillRect rect(vec2(0,y), vec2(box.w, dy))

  r.fillStyle = colorTheme.bgSelectionLabel
  r.fillRect rect(vec2(0,y), vec2(2, dy))
  
  image.draw(getIcon(explorer, file), translate(vec2(box.x + 20 + nesting_indent.toRunes.width(gt).float32, y + 4)) * scale(vec2(icon_const * dy, icon_const * dy)))

  r.image.draw text.toRunes, colorTheme.cActive, vec2(box.x + 40, y), box, gt, colorTheme.bgSelection
  y += dy


proc drawFile(
  image: Image,
  file: File,
  r: Context,
  box: Rect,
  nesting_indent: string,
  text: string,
  gt: var GlyphTable,
  bg: ColorRgb,
  y: var float32,
  dy: float32,
  icon_const: float32
  ) =

  image.draw(getIcon(file), translate(vec2(box.x + 20 + nesting_indent.toRunes.width(gt).float32, y + 4)) * scale(vec2(icon_const * dy, icon_const * dy)))

  r.image.draw text.toRunes, colorTheme.cActive, vec2(box.x + 40, y), box, gt, bg
  y += dy
    

proc drawSelectedFile(
  explorer: var SideExplorer,
  image: Image,
  file: File,
  r: Context,
  box: Rect,
  nesting_indent: string,
  text: string,
  gt: var GlyphTable,
  y: var float32,
  dy: float32,
  icon_const: float32
  ) =

  updateExplorer(explorer, file)

  r.fillStyle = colorTheme.bgSelection
  r.fillRect rect(vec2(0,y), vec2(box.w, dy))

  r.fillStyle = colorTheme.bgSelectionLabel
  r.fillRect rect(vec2(0,y), vec2(2, dy))

  image.draw(getIcon(file), translate(vec2(box.x + 20 + nesting_indent.toRunes.width(gt).float32, y + 4)) * scale(vec2(icon_const * dy, icon_const * dy)))

  r.image.draw text.toRunes, colorTheme.cActive, vec2(box.x + 40, y), box, gt, colorTheme.bgSelection
  y += dy


proc side_explorer_area*(
  r: Context,
  image: Image,
  box: Rect,
  pos: float32,
  gt: var GlyphTable,
  bg: ColorRgb,
  dir: File,
  explorer: var SideExplorer,
  count_items: int32,
  y: float32,
  nesting: int32,
  ) : (float32, int32) {.discardable.} =

  let 
    dy = round(gt.font.size * 1.40)
    icon_const = 0.06
  var 
    y = y
    dir = dir
    count_items = count_items
    size = (box.h / gt.font.size).ceil.int
  
  # ! sorted on each component rerender | check if seq already sorted or take the sort to updateDir

  var dir_files: seq[File] = @[]
  var dir_folders: seq[File] = @[]
  for file in dir.files:
    if file.info.kind == PathComponent.pcFile:
      dir_files.add(file)
    elif file.info.kind == PathComponent.pcDir:
      dir_folders.add(file)


  sort(dir_files, nameUpCmp)
  sort(dir_folders, nameUpCmp)
  dir.files = dir_folders & dir_files
  
  for i, file in dir.files.pairs:

    let nesting_indent = " ".repeat(nesting * 2)
    let text = nesting_indent & file.name & file.ext
    
    inc count_items

    case file.info.kind
    of PathComponent.pcFile:
      if count_items in pos.int..pos.ceil.int+size:
        if count_items == int(explorer.item_index):
          drawSelectedFile(explorer, image, file, r, box, nesting_indent, text, gt, y, dy, icon_const)
        else:
          drawFile(image, file, r, box, nesting_indent, text, gt, bg, y, dy, icon_const)

    of PathComponent.pcDir:
      if count_items in pos.int..pos.ceil.int+size:
        if count_items == int(explorer.item_index):
          drawSelectedDir(explorer, image, file, r, box, nesting_indent, text, gt, y, dy, icon_const)
        else:
          drawDir(explorer, image, file, r, box, nesting_indent, text, gt, bg, y, dy, icon_const)
      
      if OpenDir(path: file.path / file.name & file.ext) in explorer.open_dirs:

        dir.files[i].files = newFiles(file.path / file.name & file.ext)

        (y, count_items) = r.side_explorer_area(
          image = image,
          box = box,
          pos = pos,
          gt = gt,
          bg = bg,
          dir = dir.files[i],
          explorer = explorer,
          count_items = count_items,
          y = y,
          nesting = nesting + 1
        )

    else:
      discard
        
  explorer.count_items = count_items
  return (y, count_items)
