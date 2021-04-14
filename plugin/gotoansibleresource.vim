"
" Useful link: https://devhints.io/vimscript
"
" gotoansibleresource.vim - Helper for day2day ansible development
" Maintainer:         Remi Ferrand (riton)
" Version:            1.0
"
"

if exists('g:loaded_gotoansibleresource') || &cp
  finish
endif
let g:loaded_gotoansibleresource = 1

if !exists('g:gotoansibleresource_extra_collection_path')
  let g:gotoansibleresource_extra_collection_path = []
endif

" Initialize this to empty array, this will make this easy for
" us to later only call out the 'ansible-config' command
" once (if this variable is empty array)
let g:gotoansibleresource_discovered_collection_path = []

"
" Helpers
"
function! s:getResourceNameUnderCursor()
  " Get current WORD under cursor and remove any final ':' char
  let wordUnderCursor = substitute(expand('<cWORD>'), ':$', '', '')
  let wordUnderCursor = substitute(l:wordUnderCursor, "\['\"\]", '', 'g')
  return l:wordUnderCursor
endfunc

function! s:doesResourceNameLooksLikeFullyQualifiedName(rName)
  " Are we dealing with an Ansible Fully qualified collection name ?
  if stridx(a:rName, '.') < 0
    return 0
  endif
  return 1
endfunc

function! s:collectionExtractComponents(rName)
  let fields = split(a:rName, '\.')
  return {"author": l:fields[0], "collection_name": l:fields[1], "resource": l:fields[2:]}
endfunc

function! s:getAnsibleConfiguredCollectionPath()
  " COLLECTIONS_PATHS(default) = ['/home/user/.ansible/collections', '/usr/share/ansible/collections']
  let output = system("ansible-config dump |grep COLLECTIONS_PATHS")
  let rawColPaths = split(l:output[stridx(l:output, '[')+1:-3], ',')

  let colPaths = []
  for rawColPath in l:rawColPaths
    let cleanedColPath = substitute(rawColPath, '^ ', '', '')
    let colPaths = l:colPaths + [l:cleanedColPath[1:-2]]
  endfor

  return l:colPaths
endfunc

function! s:getCollectionSearchPaths()
  if len(g:gotoansibleresource_discovered_collection_path) == 0
    let g:gotoansibleresource_discovered_collection_path = s:getAnsibleConfiguredCollectionPath()
  endif

  return g:gotoansibleresource_discovered_collection_path + g:gotoansibleresource_extra_collection_path
endfunc

function! s:searchCollectionResource(rType, components, searchPaths)
  for searchPath in a:searchPaths
    let colPath = l:searchPath."/ansible_collections/".a:components["author"]."/".a:components["collection_name"]
    " only directory will be checked for roles
    if a:rType == 'role'
      let resourcePath = s:searchRoleInCollection(a:components['resource'][0], l:colPath)
      if l:resourcePath == ""
        continue
      endif
      return l:resourcePath
    endif

    if a:rType =~ "_plugin$"
      let resourcePath = s:searchPluginInCollection(a:rType, l:colPath."/plugins", a:components['resource'])
      if l:resourcePath == ""
        continue
      endif
      return l:resourcePath
    endif
  endfor

  return ""
endfunc

function! s:searchPluginInCollection(rType, pluginsPath, resource)
  let pluginKind = a:rType[:stridx(a:rType, '_')-1]
  let resourcePath = ""

  if l:pluginKind == "tryall"
    " This is a special value
    " that allows user to say 'try all plugins
    " type and if only one plugin type matches
    " then show me'
    " If we have multiple match, an error will be
    " displayed to user
    let resources = s:searchAllPluginTypesForResource(a:pluginsPath, a:resource)
    if len(l:resources) == 0
      return ""
    endif

    if len(l:resources) > 1
      throw "Resource ".join(a:resource, ".")." have multiple matches in different resource kinds: ".join(l:resources, ',')
    endif

    let resourcePath = l:resources[0]

  elseif l:pluginKind == "action"
    let kindPath = a:pluginsPath."/action"
  elseif l:pluginKind == "module"
    let kindPath = a:pluginsPath."/modules"
  else
    throw "Unknown pluginKind ".l:pluginKind
  endif

  if l:resourcePath == ""
    " resource can be 'foo' or 'foo.bar', etc...
    let resourcePath = l:kindPath."/".join(a:resource, '/').".py"
  endif

  if filereadable(l:resourcePath)
    return l:resourcePath
  endif

  return ""
endfunc

function! s:searchAllPluginTypesForResource(pluginPath, resource)
  let pluginTypes = ['action', 'become', 'cache', 'callback', 'cliconf',
        \ 'connection', 'doc_fragments', 'filter', 'httpapi', 'inventory', 'lookup',
        \ 'netconf', 'shell', 'strategy', 'terminal', 'test', 'vars', 'modules']

  let resourcesPaths = []
  for pluginType in l:pluginTypes
    let resourcePath = a:pluginPath."/".l:pluginType."/".join(a:resource, '/').".py"
    if filereadable(l:resourcePath)
      let resourcesPaths = l:resourcesPaths + [l:resourcePath]
    endif
  endfor

  return l:resourcesPaths
endfunc

function! s:searchRoleInCollection(rName, colPath)
  let rolePath = a:colPath."/roles/".a:rName
  if !isdirectory(l:rolePath)
    return ""
  endif

  return l:rolePath
endfunc

"
" Public function
"
function! gotoansibleresource#gotoAnsibleResource(rType)
  let cResourceName = s:getResourceNameUnderCursor()

  if s:doesResourceNameLooksLikeFullyQualifiedName(l:cResourceName) == 1
    let colSearchPaths = s:getCollectionSearchPaths()
    let colComponents = s:collectionExtractComponents(l:cResourceName)

    let resourcePath = s:searchCollectionResource(a:rType, l:colComponents, l:colSearchPaths)
    if l:resourcePath == ""
      echoerr string(l:colComponents)." not found in ".join(l:colSearchPaths, ',')
      return
    endif
  endif

  " For a role, just open the main role directory folder
  " This avoids to deal with 'tasks_from' or any other stuff for now
  if a:rType == "role" || a:rType =~ "_plugin$"
    execute "vsplit | view ".l:resourcePath
    return
  endif
endfunc

command! GotoAnsibleRole call gotoansibleresource#gotoAnsibleResource('role')
command! GotoAnsiblePlugin call gotoansibleresource#gotoAnsibleResource('tryall_plugin')
command! GotoAnsibleActionPlugin call gotoansibleresource#gotoAnsibleResource('action_plugin')
command! GotoAnsibleModulePlugin call gotoansibleresource#gotoAnsibleResource('module_plugin')
