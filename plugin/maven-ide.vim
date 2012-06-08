"=============================================================================
" File:        maven-ide.vim
" Author:      Daren Isaacs (ikkyisaacs at gmail.com)
" Last Change: Thu Jun  7 22:37:44 EST 2012
" Version:     0.5
"=============================================================================
" See documentation in accompanying help file.
" You may use this code in whatever way you see fit.

"{{{ Project ------------------------------------------------------------------
function! MvnGetProjectDirList(projectCount, excludeSubProjects) "{{{
"Build a list of project directories from the 'project' buffer starting 
"   under the cursor.
"projectCount - the number of parent projects directories to return. -1 return all 
"   projects from the cursor to the end.
"excludeSubProjects - set 1 to return only top level projects, 
"    0 includes subprojects.
"return - a list of project directories.
"{{{ body
    let l:projectDirList = []
    let l:save_cursor = getpos('.')
    let l:finish = 0
    let l:counter = 0
    let l:projectCount = a:projectCount
    let l:prjRegExp = "^\\s*.\\+in=in.vim"
    if a:excludeSubProjects
        let l:prjRegExp = "^\\S.\\+in=in.vim"
    endif
    if strlen(l:projectCount) == 0
        call inputsave()
        let l:projectCount = input("Enter the project count:")
        call inputrestore()
    endif 
    if strlen(l:projectCount) == 0
        let l:projectCount = -1
    endif
    
    let l:projectDir = MvnGetProjectDir(l:save_cursor[1])
    if !strlen(l:projectDir) > 0 
        echo("Error - Current line is not a project header!")
        return l:projectDirList
    endif 

    while !l:finish 
        let l:projectLineNo = search(l:prjRegExp, 'Wc')   
        if l:projectLineNo == 0
            let l:finish = 1
        else
            let l:projectDir = MvnGetProjectDir(l:projectLineNo)
            if strlen(l:projectDir) > 0 
                if -1 == match(getline(l:projectLineNo), "^\\s")
                    let l:counter += 1 "is a parent
                endif
                if l:counter > l:projectCount && l:projectCount != -1
                    let l:finish = 1       
                else
                    call add(l:projectDirList, l:projectDir)
                endif 
            endif
            call cursor(l:projectLineNo + 1, l:save_cursor[2])
        endif
    endwhile

    call setpos('.', l:save_cursor)
    return l:projectDirList
endfunction; "}}} body }}}

function! MvnGetProjectDir(projectLineNo) "{{{
"Get the project directory from the project config file using the given 
"   line number.
"{{{ body
    let l:line = getline(a:projectLineNo)
    let l:projectDir = matchstr(l:line, '=\@<=\([/A-Za-z0-9_-]\+\)', 0, 1)
    if strlen(l:projectDir) > 0 && filereadable(l:projectDir."/pom.xml")
        return l:projectDir
    endif
    return ""
endfunction; "}}} body }}}

function! MvnInsertProjectTree() "{{{
    if strlen(s:mvn_defaultProject) == 0
        let s:mvn_defaultProject = matchstr(system("pwd"), "\\p\\+") 
    endif
    call inputsave()
    let l:mvnProjectPath = input("Enter the maven project path:", s:mvn_defaultProject, "file")
    call inputrestore()
    if !isdirectory(l:mvnProjectPath)
        echo("Invalid Directory: ".l:mvnProjectPath)
        return
    endif
    let l:specificProject = 0
    if filereadable(l:mvnProjectPath."/pom.xml") 
        let l:specificProject = 1
    endif
    let s:mvn_defaultProject = l:mvnProjectPath

    let l:cmd = "find ".l:mvnProjectPath." -name pom.xml -print"
    let l:pomList = split(system(l:cmd))
    call sort(l:pomList)
    call reverse(l:pomList) "Build the dependencies first.

    "Does all the work.
    let l:prjData = MvnBuildProjectTree(l:pomList)

    "Insert the tree into current file (should be a project file).
    let l:insertPoint = line(".")
    call append(l:insertPoint, l:prjData.prjTreeTxt)

    "Update the project id dictionary in the project.
    "This dictionary is used to include the source path of a project 
    "in a dependant project (from MvnBuildEnv).
    let l:dict = MvnGetLocalDependencyDict()
    call extend(l:dict, l:prjData.prjIdPath, "force")
    call MvnSetLocalDependencyDict(l:dict)
endfunction; "}}}

function! MvnBuildProjectTree(pomList) "{{{
"Build a Project directory tree maven style in the cursor position in the current file.
"Hard coded standard maven src/resource dirs.
"Prompts for location of the maven project, default is pwd.
"On completion use Project \R to populate with files.
"return - a map {List prjTreeTxt, Dictionary prjIdPath}
"   prjIdPath - key: project unique identifier, value: the project path.
"{{{ body
    let l:prjTreeTxt = []
    let l:prjIdPath = {}
    let l:fileFilter = join(g:mvn_javaSrcFilterList,' ').' '.join(g:mvn_resourceFilterList, ' ')
    let l:javaSrcExtList = MvnFilterToExtList(g:mvn_javaSrcFilterList)
    let l:javaResrcExtList = MvnFilterToExtList(g:mvn_resourceFilterList)
    "mvn project directory entry.
    let l:currentPom = 0
    let l:prjIndx = 0 
    let l:indentCount = 0
    while l:currentPom < len(a:pomList)
        let l:currentPom = MvnCreateSingleProjectEntry(a:pomList, l:currentPom, l:prjTreeTxt,
            \ l:prjIndx, l:javaSrcExtList, l:javaResrcExtList, l:fileFilter, indentCount,
            \ l:prjIdPath)
        let l:currentPom += 1
    endwhile
    return {'prjTreeTxt': l:prjTreeTxt, 'prjIdPath': l:prjIdPath}
endfunction; "}}} body }}}

"{{{ project local dependency dict
function! MvnUpdateProjectIdDict(projectPath, id) "{{{
"Update the project file with the dependency id for the project
"   ie the form of groupId:artifactId:version
    let l:dict = MvnGetLocalDependencyDict()
    let l:dict[a:id] = a:projectPath
    call MvnSetLocalDependencyDict(l:dict)
endfunction; "}}}

function! MvnGetLocalDependencyDict() "{{{
"The current buffer must be the project file.
    let l:MARKER = '#PROJECT_IDS='
    let save_cursor = getpos(".")
    let l:dependsLineNo= search(l:MARKER)
    call setpos('.', save_cursor)
    let l:dict = {}
    if l:dependsLineNo > 0
        let l:dependLine = getline(l:dependsLineNo)
        let l:dictStart = matchend(l:dependLine, l:MARKER)
        let l:dict = eval(strpart(l:dependLine, l:dictStart))
    endif
    return l:dict
endfunction; "}}}

function! MvnSetLocalDependencyDict(dict) "{{{
"The current buffer must be the project file.
    let l:MARKER = '#PROJECT_IDS='
    let save_cursor = getpos(".")
    let l:dependsLineNo= search(l:MARKER)
    call setpos('.', save_cursor)
    if l:dependsLineNo > 0
        call setline(l:dependsLineNo, l:MARKER.string(a:dict)) 
    else
        call append(line('$'), l:MARKER.string(a:dict)) 
    endif
endfunction; "}}}
"}}} project local dependency dict

"{{{ tree build functions 
 "{{{ MvnCreateSingleProjectEntry
function! MvnCreateSingleProjectEntry(pomList, currentPom, prjTreeTxt, 
        \ prjIndx, srcExtList, resrcExtList, fileFilter, indentCount, 
        \ prjIdPath)
"Build the tree structure into a:prjTreeTxt for the maven top level dirs:
"   src/main/java, src/main/resources, src/main/webapp, src/test/java
"   src/tset/resources. Recursively build subprojects.
"a:pomList - the list of poms for a project and its child projects.
"a:currentPom - an index into a:pomList.
"a:prjTreeTxt - a list containing the text for the view of the project.
"a:prjIndx - the insert point for new tree text into a:prjTreeTxt list. 
"   Decremented on the recursive call.
"a:srcExtList, a:resrcExtList - the filename extensions to search on in
"   the creation of the directory tree.
"a:fileFilter - the extensions (ie txt,java...) as filters (ie *.txt,*.java)
"a:indentCount - the indentation (number of spaces) for the tree text. 
"   Incrmented on each recursive call.

    let l:pomFile = a:pomList[a:currentPom]
    let l:projectPath = substitute(l:pomFile, "/pom.xml", "", "g")
    let l:projectName = matchstr(l:projectPath, "[^/]\\+.$") 
    let l:allExtList = extend(extend([], a:srcExtList), a:resrcExtList)

    call insert(a:prjTreeTxt, repeat(' ', a:indentCount).l:projectName."="
        \  .l:projectPath." CD=. in=in.vim filter=\"".a:fileFilter."\" {", a:prjIndx)

    if a:prjIndx < 0
        call insert(a:prjTreeTxt, repeat(' ', a:indentCount)."}", a:prjIndx)
    else
        call add(a:prjTreeTxt, repeat(' ', a:indentCount)."}")
    endif

    "src main package dirs.
    call MvnBuildTopLevelDirEntries("srcMain", l:projectPath, s:mvn_projectMainSrc,
        \ a:prjTreeTxt, a:prjIndx - 1, a:srcExtList, a:indentCount)
    call MvnBuildTopLevelDirEntries("webapp", l:projectPath, s:mvn_projectMainWebapp,
        \ a:prjTreeTxt, a:prjIndx - 1, l:allExtList, a:indentCount)
    "src test package dirs.
    call MvnBuildTopLevelDirEntries("srcTest", l:projectPath, s:mvn_projectTestSrc,
        \ a:prjTreeTxt, a:prjIndx - 1, a:srcExtList, a:indentCount)
    "resource dirs.
    call MvnBuildTopLevelDirEntries("resrcMain", l:projectPath, s:mvn_projectMainResources,
        \ a:prjTreeTxt, a:prjIndx - 1, a:resrcExtList, a:indentCount)
    call MvnBuildTopLevelDirEntries("resrcTest", l:projectPath, s:mvn_projectTestResources,
        \ a:prjTreeTxt, a:prjIndx - 1, a:resrcExtList, a:indentCount)
    "add the mvn project id to the project file.
    let l:projectId = MvnGetPomId(l:projectPath."/pom.xml")
    "call MvnUpdateProjectIdDict(l:projectPath, l:projectId) 
    let a:prjIdPath[l:projectId] = l:projectPath

    let l:currentPom = a:currentPom
    let l:isChild = 1
    while !(l:currentPom + 1 > len(a:pomList) - 1) && l:isChild
        let l:nextPomFile = a:pomList[l:currentPom + 1]
        let l:nextProjectPath = substitute(l:nextPomFile, "/pom.xml", "", "g")
        let l:isChild = match(l:nextProjectPath, l:projectPath) > -1
        if l:isChild 
            let l:currentPom = MvnCreateSingleProjectEntry(a:pomList, l:currentPom + 1, a:prjTreeTxt,
                \ a:prjIndx - 1, a:srcExtList, a:resrcExtList, a:fileFilter, a:indentCount + 1,
                \ a:prjIdPath) 
        endif
    endwhile
    return l:currentPom 
endfunction; "}}} MvnCreateSingleProjectEntry

"{{{ MvnBuildTopeLevelDirEntries 
function! MvnBuildTopLevelDirEntries(dirName, mvnProjectPath, relativePath,  
        \masterProjectEntry, masterProjectIndx, javaSrcExtList, indentCount)
"Construct the directories for a maven project. Called once for each of:
"   src/main/java, src/main/resources, src/main/webapp, src/test/java,
"   src/test/resources
    if isdirectory(a:mvnProjectPath."/".a:relativePath)
        let l:dirEntry = MvnBuildDirEntry(a:dirName, a:relativePath, a:indentCount + 1)
        let l:mainPackageList = MvnBuildDirList(a:mvnProjectPath, "/".a:relativePath."/", a:javaSrcExtList)
        let l:mainPackageEntries = MvnBuildSiblingDirEntries(l:mainPackageList, a:indentCount + 2)
        call extend(l:dirEntry, l:mainPackageEntries, -1)
        call extend(a:masterProjectEntry, l:dirEntry, a:masterProjectIndx)
    endif
endfunction; "}}} MvnBuildTopeLevelDirEntries 

function! MvnBuildSiblingDirEntries(dirList, indentCount) "{{{ 2 
"Create a list with elements representing the directory list. 
"Return - the list representing the dirList of sibling directories.
    let l:dirEntries = []
    for dirName in a:dirList
        let l:dirEntry = MvnBuildDirEntry(substitute(dirName, "/", ".", "g"), dirName, a:indentCount)
        call extend(l:dirEntries, l:dirEntry)
    endfor
    return l:dirEntries
endfunction; "}}} 2

function! MvnBuildDirEntry(dirName, dirPath, indentCount) "{{{ 2 
"Create an entry for a new directory.
"Return - a 2 element list representing the directory.
    let l:dirEntry = []
    call add(l:dirEntry, repeat(' ', a:indentCount).a:dirName."=".a:dirPath." {")
    call add(l:dirEntry, repeat(' ', a:indentCount)."}")
    return l:dirEntry
endfunction; "}}} 2

function! MvnBuildDirList(mvnProjectPath, projectComponentDir, extensionList) "{{{ 2
"Find directories containing relevant files.
"mvnProjectPath - the dir containing the pom.
"projectComponentDir - ie /src/main/java/, /src/test/java/
"extensionList - a list of acceptable filetypes ie java, html, js, xml, js
"Return - a list of directories containing the relevant files.
    let l:cmd = "find ".a:mvnProjectPath.a:projectComponentDir."  -print"
    let l:filesList = split(system(l:cmd))
    let l:directoryList= []
    for absoluteFilename in l:filesList
        if !isdirectory(absoluteFilename) "directories must contain files
            let l:extension = matchstr(absoluteFilename, "\\.[^.]\\+$") 
            let l:extension = substitute(l:extension, ".", "", "")
            if MvnIsInList(a:extensionList, l:extension) "only add directories for file types we care about
                let l:relativeName = matchstr(absoluteFilename, "[^/]\\+.$")
                let l:packageDir = substitute(absoluteFilename, "\/[^/]\\+.$", "", "") 
                if match(l:packageDir."/",  a:projectComponentDir."$") == -1
                    let l:pos = matchend(l:packageDir, a:projectComponentDir )
                    let l:packageName = strpart(l:packageDir, l:pos)
                    if !MvnIsInList(l:directoryList, l:packageName)       
                        call add(l:directoryList, l:packageName)
                    endif
                endif 
            endif
        endif
    endfor
    return l:directoryList
endfunction; "}}} 2

function! MvnIsInList(list, value) "{{{ 2
"Could have used index(list, value) >= 0
    for item in a:list
        if item == a:value
            return 1
        endif
    endfor
    return 0
endfunction; "}}} 2 

function! MvnTrimStringPre(str, exp) 
"Trim the string up to the first exp
"Return - the str minus leading chars up to the start of exp.
    let l:result = ""
    let l:pos = match(a:str, a:exp)
    if l:pos > -1
        let l:result = strpart(a:str, l:pos) 
    endif
    return l:result
endfunction

function! MvnTrimStringPost(str, exp) 
"Trim the string after the last exp match.
"Return - the str minus chars after the end of exp.
    let l:result = "" 
    let l:pos = matchend(a:str, a:exp)
    if l:pos > -1
        let l:result = strpart(a:str, 0, l:pos) 
    endif
    return l:result
endfunction

function! MvnFilterToExtList(fileFilterList) "{{{ 2
"Strip the *. from the extension ie '*.java' becomes 'java'.
"fileFilterList - the list of file filters.
"Return - the list of extensions.
    let l:fileExtList = []
    for filter in a:fileFilterList
        let l:extension = matchstr(filter, "\\w\\+")
        call add(l:fileExtList, l:extension) 
    endfor
    return l:fileExtList
endfunction; "}}} 2
"}}} tree build functions 

"{{{ xml pom functions
function! MvnGetPomDependencies(mvnData) "{{{ 2 
"Build a list of dependencies for a maven project.
"Return a list of dependency id's for a project in the form of:
"  groupId:artifactId:version
"{{{ 3
    let l:query = "/project/dependencies/*"
    let l:effectivePom = a:mvnData
    let l:effectivePom = MvnTrimStringPre(l:effectivePom, "<project ")
    let l:effectivePom = MvnTrimStringPost(l:effectivePom, "</project>")
    let l:effectivePom = substitute(l:effectivePom, "\n", "", "g")
    call writefile([l:effectivePom], s:mvn_tmpdir."/effective-pom.xml")
    let l:rawDependencyList = MvnGetXPath(s:mvn_tmpdir."/effective-pom.xml", l:query)
    call delete(s:mvn_tmpdir."/effective-pom.xml")
    let l:dependencyNodeList = MvnParseNodesToList(l:rawDependencyList) 
    let l:dependencyIdList = MvnGetDependencyIdList(l:dependencyNodeList)
    return l:dependencyIdList
endfunction; "}}} 3 }}} 2

function! MvnGetDependencyIdList(dependencyNodeList) "{{{ 2 
"Compose the id from each dependency node fragment.
"Return - a list of dependency id's of for groupId:artifactId:version
"{{{ 3
    let l:idDependencyList = []
    for nodeText in a:dependencyNodeList
        let l:query = "/dependency/groupId/text\(\)"
        let l:groupId = get(MvnGetXPathFromTxt(nodeText, l:query), 2)
        let l:query = "/dependency/artifactId/text\(\)"
        let l:artifactId = get(MvnGetXPathFromTxt(nodeText, l:query), 2)
        let l:query = "/dependency/version/text\(\)"
        let l:version = get(MvnGetXPathFromTxt(nodeText, l:query), 2)
        call add(idDependencyList, l:groupId.":".l:artifactId.":".l:version)
    endfor
    return l:idDependencyList
endfunction; "}}} 3 }}} 2

function! MvnParseNodesToList(xpathOutputList) "{{{ 2
"Take the string output from xpath and create a list item for each node.
"xpathOutputList - the xpath string result from a query as a list.
"Return - cleaned xpath output as a list - one node in each list item.
"{{{ 3
    let l:item = ""
    let l:haveNode = 0
    let l:lineList = []
    for line in a:xpathOutputList
        let l:pos = match(line, "\\c-- node --") 
        if l:pos > -1 
            if l:pos > 0
                "-- node -- separator is not always on a new line!
                let l:item .= strpart(line, 0, l:pos)
            endif 
            if strlen(l:item) > 0 
                call add(l:lineList, l:item)
                let l:item = ""
            endif
            let l:haveNode = 1
        elseif l:haveNode == 1
            let l:item .= matchstr(line, "\\p\\+")
        endif
    endfor
    if strlen(l:item) > 0 
        call add(l:lineList, l:item)
    endif
    return l:lineList 
endfunction; "}}} 3 }}} 2

function! MvnGetPomId(pomFile) "{{{ 2 
"Build an identifier for a maven project in the form groupId:artifactId:version
"pomFile - path/filname of the pom.xml.
"Return - the project identifier ie groupId:artifactId:version.
"{{{ 3
    let l:query = "/project/groupId/text\(\)"
    let l:groupId = get(MvnGetXPath(a:pomFile, l:query), 2)
    let l:query = "/project/artifactId/text\(\)"
    let l:artifactId = get(MvnGetXPath(a:pomFile, l:query), 2)
    let l:query = "/project/version/text\(\)"
    let l:version = get(MvnGetXPath(a:pomFile, l:query), 2)
    return l:groupId.":".l:artifactId.":".l:version
endfunction; "}}} 3 }}} 2

function! MvnGetXPathFromTxt(xmlText, query) "{{{ 2 
"xmlText- the xml string to parse.
"query - the XPath query.
"Return a list query data.
"{{{ 3
    let l:cmd = substitute(s:mvn_xpathcmd, "filename", "", 'g') 
    let l:cmd = substitute(l:cmd, "query", a:query, 'g')
    let l:resultList= split(system("echo \"".a:xmlText."\" |".l:cmd), "\n")
    return l:resultList
endfunction; "}}} 3 }}} 2

function! MvnGetXPath(xmlFile, query) "{{{ 2 
"xmlFile - the path/filename of the xmlfile.
"query - the XPath query.
"Return a list query data.
"{{{ 3
    let l:cmd = substitute(s:mvn_xpathcmd, "filename", a:xmlFile, 'g') 
    let l:cmd = substitute(l:cmd, "query", a:query, 'g')
    let l:resultList= split(system(l:cmd), "\n")
    return l:resultList
endfunction; "}}} 3 }}} 2
"}}} xml pom functions
"}}} Project ------------------------------------------------------------------

"{{{ Environment config -------------------------------------------------------
let s:mvn_errorString = ""
function! MvnBuildEnvSelection() "{{{
"Build the environment for the consecutive project entries.
"{{{ body
    let l:dirList = MvnGetProjectDirList("", 0)
    let l:currentDir = getcwd()
    for dir in l:dirList
        exec 'cd '.dir
        call MvnBuildEnv(dir)
    endfor
    exec 'cd '.l:currentDir
endfunction; "}}} body }}}

function! MvnBuildEnv(projectHomePath) "{{{
"Build the project in.vim sourced on access to a file in the project. Environment generated:
"g:vjde_lib_path, g:mvn_javadocPath, g:mvn_javaSourcePath, g:mvn_projectHome, path, tags.
"The paths include local project dependencies in the project file via the #PROJECT_IDS
"stored at the bottom of the project file and maintained during MvnBuildProjectTree.
"{{{ body
    let s:mvn_errorString = ""
    let l:projectHomePath = a:projectHomePath
    if strlen(l:projectHomePath) == 0
        let l:projectHomePath = MvnGetProjectHomeDir()
        if !filereadable(l:projectHomePath."/pom.xml") 
            echo("No project file :".l:projectHomePath."/pom.xml")
            return
        endif 
    endif
    echo("\nBuild env for ".l:projectHomePath.".")
    let l:newline = "let g:mvn_projectHome=\"".l:projectHomePath."\""
    call MvnUpdateFile("in.vim", "mvn_projectHome", l:newline)

    "Run 2 goals with a single invocation of maven. Get the effective pom and classpath.
    let l:mvnData = system("cd ".l:projectHomePath."; "
        \."mvn org.apache.maven.plugins:maven-dependency-plugin:2.4:build-classpath"
        \." org.apache.maven.plugins:maven-help-plugin:2.1.1:effective-pom")

    "echo("Calculate local project dependencies from mvn help:effective-pom.")
    "Get the maven local sibling dependencies for a project to add to the path instead of jars.
    let l:siblingProjectDirs = MvnGetLocalDependenciesList(l:mvnData)
    let l:projectDirList = insert(l:siblingProjectDirs, l:projectHomePath) 

    "Create the runtime classpath for the maven project.
    "echo("Calculate the runtime classpath using mvn dependency:build-classpath.") 21sec
    let l:mvnClassPath = MvnBuildRunClassPath(l:mvnData)
    if strlen(l:mvnClassPath) == 0
        echo("No classpath. ".s:mvn_errorString)
        return
    endif

    "echo("Calculate the jdk runtime library using java -verbose -h.") 
    let l:jreLib = MvnGetJreRuntimeLib() 
    let l:projectRuntimeDirs = MvnGetPathFromDirsByAppend(l:projectDirList, s:mvn_projectMainClasses)
    "Add l:projectRuntimeDirs (target/classes) to the path ahead of l:mvnClassPath (the jars).
    let l:newline = "let g:vjde_lib_path=\"".l:projectRuntimeDirs.":".l:jreLib.":".l:mvnClassPath."\""
    call MvnUpdateFile("in.vim", "vjde_lib_path", l:newline) 

    "Install javadoc (if the jars exist) and create the path to the javadoc for the maven project.
    "echo("Unpack javadoc if downloaded and create javadoc path.") 
    let l:javadocPath = MvnInstallArtifactByClassifier(g:mvn_javadocParentDir, l:mvnClassPath, "javadoc")
    let l:newline = "let g:mvn_javadocPath=\"".l:javadocPath.":".g:mvn_additionalJavadocPath."\""
    call MvnUpdateFile("in.vim", "mvn_javadocPath", l:newline) 

    "Install java sources (if the jars exist) and create the path to the sources for the maven project.
    "echo("Unpack dependency source if downloaded and create source path.") 
    let l:javaSourcePath = MvnInstallArtifactByClassifier(g:mvn_javaSourceParentDir, l:mvnClassPath, "sources")
    let l:javaSourcePath .= ":".g:mvn_additionalJavaSourcePath
    let l:projectJavaSourcePath = MvnGetPathFromDirsByAppend(l:projectDirList, s:mvn_projectMainSrc)
    let l:javaSourcePath = l:projectJavaSourcePath . ":" . l:javaSourcePath
    let l:javaSourcePath = substitute(l:javaSourcePath, '::\+', ':', 'g')
    let l:newline = "let g:mvn_javaSourcePath=\"".l:javaSourcePath."\""
    call MvnUpdateFile("in.vim", "mvn_javaSourcePath", l:newline) 

    "set path. Include test source to allow for quick fix of junit failures 
    "ie during mvn clean install.
    let l:javaSourcePath .= ':'.l:projectHomePath.'/'.s:mvn_projectTestSrc
    let l:path = MvnConvertToPath(l:javaSourcePath)
    let l:newline = "let &path=\"".l:path."\""
    call MvnUpdateFile("in.vim", "let &path=", l:newline) 

    "echo("Build tag files for all available source files.")
    let l:tagPath = MvnBuildTags(l:javaSourcePath, l:projectHomePath)
    let l:newline = "let &tags=\"".l:tagPath."\""
    call MvnUpdateFile("in.vim", "tags", l:newline) 
    echo "MvnBuildEnv Complete. " . s:mvn_errorString
endfunction; "}}} body }}}

function! MvnConvertToPath(javaSourcePath) "{{{
"Return - the vim path from javaSourcePath.
    let l:pathList = split(a:javaSourcePath, ':')
    let l:path = ''
    for branch in l:pathList
        let l:path .= branch.'/'.'**,'
    endfor
    if strpart(l:path, len(l:path)-1, 1) == ','  
        let l:path = strpart(l:path, 0, len(l:path)-1)
    endif
    return l:path
endfunction; "}}}

function! MvnGetLocalDependenciesList(mvnData) "{{{
"Return a list of paths to local sibling projects depended on by this project. 
    let l:dependencyList = MvnGetPomDependencies(a:mvnData)
    let l:dependencyDict = MvnGetLocalDependencyDict()
    let l:localDependencyPath = []
    for dependency in l:dependencyList
        if has_key(l:dependencyDict, dependency)
            call add(l:localDependencyPath, l:dependencyDict[dependency])
        endif
    endfor
    return l:localDependencyPath
endfunction; "}}}

function! MvnGetPathFromDirsByAppend(dirList, childDir) "{{{
"Return a path by appending the childDir to each dir in the list.
"dirList - the list of parent dirs eg /opt/work/project
"childDir - ie target/classes
    let l:dirs = []
    for tmpdir in a:dirList
        call add(l:dirs, tmpdir."/".a:childDir)
    endfor
    let l:dirPath = join(l:dirs, ":")  
    return l:dirPath
endfunction; "}}}

function! MvnGetProjectHomeDir() "{{{
"return - the absolute path for the project ie where the pom.xml is. 
    let l:projTargetClassesPath = matchstr(system('pwd'), "\\p\\+")
    return l:projTargetClassesPath
endfunction; "}}}

function! MvnGetJreRuntimeLib() "{{{
    let l:jreLib = matchstr(system("java -verbose -h |grep Opened"), "Opened \\p\\+")
    let l:jreLib = matchstr(l:jreLib, "/.\\+jar")
    return l:jreLib
endfunction; "}}}

function! MvnBuildRunClassPath(mvnData) "{{{
"Create the classpath from the maven project.
"return - the maven classpath
    "let l:runMaven ='mvn dependency:build-classpath'  
    "let l:mavenClasspathOutput = system(l:runMaven)
    let l:mavenClasspathOutput = a:mvnData
    let l:pos = matchend(l:mavenClasspathOutput, 'Dependencies classpath:')
    let l:clpath = "" 
    if l:pos != -1
        let l:endPos = match(l:mavenClasspathOutput, '\[INFO\]', l:pos)
        "let l:clpath = matchstr(l:mavenClasspathOutput, "\\p\\+", l:pos)
        let l:clpath = strpart(l:mavenClasspathOutput, l:pos, l:endPos-l:pos)
        let l:clpath = substitute(l:clpath, '\n', '', 'g')
    else
        let s:mvn_errorString .= " MvnBuildRunClassPath():Failed on mvn dependency:build-classpath.".l:pos
    endif
    return l:clpath
endfunction; "}}}

function! MvnUpdateFile(filename, id, newline) "{{{
"Update the in.vim Project file. Lookup the line by a:id ie the environment
"  variable name and replace with a:newline. If an entry for the variable 
"  does not exist in the file then add it.
    if filereadable(a:filename)
        let l:lines = readfile(a:filename)
    else
        let l:lines = []
    endif
    let l:lineNo = match(l:lines, a:id)
    if l:lineNo >= 0
        call remove(l:lines, l:lineNo)
    else
        let l:lineNo = 0
    endif
        call insert(l:lines, a:newline, l:lineNo)
        call writefile(l:lines, a:filename)
endfunction; "}}}
"}}} Environment config -------------------------------------------------------

"{{{ Compiler -----------------------------------------------------------------
"{{{ mavenOutputProcessorPlugins
"plugins to parse maven output to a quickfix list ie junit,checkstyle...
let s:MvnPlugin = {} "{{{ mavenProcessorParentPlugin
function! s:MvnPlugin.New()
    let l:newMvnPlugin = copy(self)
    let l:newMvnPlugin._mvnOutputList = []
    let l:newMvnPlugin._startRegExpList = [] 
    let l:newMvnPlugin._currentLine = 0
    return l:newMvnPlugin
endfunction
function! s:MvnPlugin.addStartRegExp(regExp) dict
    call add(self._startRegExpList, a:regExp)
endfunction
function! s:MvnPlugin.processErrors() dict
    let l:ret = {'lineNumber': a:lineNo, 'quickfixList': []}
    return l:ret
endfunction
function! s:MvnPlugin.setOutputList(mvnOutputList) dict
    let self._mvnOutputList = a:mvnOutputList
endfunction
function! s:MvnPlugin.processAtLine(lineNo) dict "{{{ processAtLine
"Check the lineNo for the plugin message
"a:mvnOutputList - the complete mvn output log as a list.
"a:lineNo - the line number of the mvnOutputList to begin processing.
"return dict { lineNumber, quickfixList }
"   lineNumber  - set as the input lineNo when no processing occurred,
"   otherwise the final line of processing.
"   quickfixList - a quickfix list resulting from the processing of the
"   log lines. quickfix dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': a:lineNo, 'quickfixList': []}
    let self._currentLine = a:lineNo
    let l:fail = 1
    for regExp in self._startRegExpList   
        if match(self._mvnOutputList[self._currentLine], regExp) != 0 
            return l:ret 
        endif
        let self._currentLine += 1
    endfor
    let l:ret = self.processErrors()
    return  l:ret
endfunction "}}} processAtLine }}} mavenProcessorParent

let s:Mvn2Plugin = {} "{{{ maven2Plugin
function! s:Mvn2Plugin.New()
   let this = copy(self)
   let super = s:MvnPlugin.New()
   call extend(this, deepcopy(super), "keep")
   call this.addStartRegExp('^\[ERROR\] BUILD FAILURE')
   call this.addStartRegExp('^\[INFO\] -\+')
   call this.addStartRegExp('^\[INFO\] Compilation failure')
   return this 
endfunction
function! s:Mvn2Plugin.processErrors()
    let l:ret = {'lineNumber': a:lineNo, 'quickfixList': []}
    return l:ret
endfunction
function! s:Mvn2Plugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}

    let l:errorFinish = match(self._mvnOutputList, '^\[INFO\] -\+',
        \ self._currentLine + 1)
    let l:quickfixList = []
    let l:lineNo = self._currentLine + 1
    if l:errorFinish > -1 
        while l:lineNo < l:errorFinish             
            let l:line = self._mvnOutputList[l:lineNo]
            try
                if len(l:line) == 0
                    let l:lineNo += 1
                    continue
                endif
                let l:posStart = 0        
                let l:posEnd = match(l:line, ':')
                let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:posEnd = match(l:line, ',', l:posStart)
                let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ']', l:posStart)
                let l:errorColNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:message = strpart(l:line, l:posStart)
                let l:fixList = {'bufnr': '', 'filename': l:filename, 
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixList)
                let l:lineNo += 1
            catch /notErrorLine/
                let l:exception=1
            endtry
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:lineNo
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction "}}} processErrors }}} maven2Plugin

let s:Mvn3Plugin = {} "{{{ maven3Plugin
function! s:Mvn3Plugin.New()
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^\[ERROR\] COMPILATION ERROR :')
    return this 
endfunction
function! s:Mvn3Plugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}

    let l:errorFinish = match(self._mvnOutputList, '^\[INFO\] \d\+ error',
        \ self._currentLine + 1)
    let l:quickfixList = []
    if l:errorFinish > -1 
        let l:lineNo = self._currentLine + 1 
        while l:lineNo < l:errorFinish             
            let l:line = self._mvnOutputList[l:lineNo]
            try
                if 0 != match(l:line, '\[ERROR\]')
                    throw 'notErrorLine' 
                endif
                let l:posStart = 8        
                let l:posEnd = match(l:line, ':')
                let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:posEnd = match(l:line, ',', l:posStart)
                let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ']', l:posStart)
                let l:errorColNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:message = strpart(l:line, l:posStart)

                let l:fixList = {'bufnr': '', 'filename': l:filename, 
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixList)

            catch /notErrorLine/
                let l:exception=1
            endtry
            let l:lineNo += 1
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:lineNo
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction "}}} processErrors }}} maven3Plugin

let s:JunitPlugin = {} "{{{ junitPlugin
function! s:JunitPlugin.New()
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    return this
endfunction "}}} junitPlugin

let s:Junit3Plugin = {} "{{{ junit3Plugin
function! s:Junit3Plugin.New()
    let this= copy(self)
    let super = s:JunitPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^ T E S T S')
    call this.addStartRegExp('^-\+')
    return this
endfunction
function! s:Junit3Plugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}
    let l:testFinish = match(self._mvnOutputList, '^Results :',
        \ self._currentLine + 1)
    if l:testFinish != -1
        let l:testFinish = match(self._mvnOutputList, '^Tests run:',
            \ l:testFinish)
    endif

    let l:quickfixList = []
    if l:testFinish > -1 
        let l:lineNo = self._currentLine + 1 
        while l:lineNo < l:testFinish             
            let l:line = self._mvnOutputList[l:lineNo]
            if (-1 != match(l:line, '<<< FAILURE!$') ||
                \ -1 != match(l:line, '<<< ERROR!$')) &&
                \ -1 == match(l:line, '^Tests run:')
                let l:resultDict = self.doFailure(l:lineNo, l:testFinish) 
                let l:fixList = l:resultDict.fixList
                let l:lineNo = l:resultDict.lineNo
                call add(l:quickfixList, l:fixList)
            endif
            let l:lineNo += 1
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:testFinish
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction
function! s:Junit3Plugin.doFailure(lineNo, finishLineNo)
    let l:lineNo = a:lineNo + 1
    let l:message = self._mvnOutputList[l:lineNo]
    let l:failFinishLine = match(self._mvnOutputList, '^$', l:lineNo)
    if l:failFinishLine > a:finishLineNo
        throw "Unable to parse Junit error."
    endif
    let l:line = self._mvnOutputList[l:failFinishLine - 1]
    let l:posStart = match(l:line, '(') + 1
    let l:posEnd = match(l:line, ':')
    let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
    let l:posStart = l:posEnd + 1
    let l:posEnd = match(l:line, ')', l:posStart)
    let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
    let l:fileNoExt = strpart(l:filename, 0, strridx(l:filename, '.'))
    let l:posStart = matchend(l:line, '^\s\+at\s\+') 
    let l:posEnd = match(l:line, '.'.l:fileNoExt)
    let l:package = strpart(l:line, l:posStart, l:posEnd-l:posStart)
    let l:classname = l:package.'.'.l:fileNoExt
    let l:filename = substitute(l:classname, '\.', '/', 'g') 
    let l:filename .= '.java'
    let l:absoluteFilename = findfile(l:filename)

    let l:fixList = {'bufnr': '', 'filename': l:absoluteFilename, 
        \'lnum': l:errorLineNo, 'pattern': '', 'col': '',
       \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

    return {'lineNo': l:failFinishLine, 'fixList': l:fixList }
endfunction "}}} processErrors }}} junit3Plugin

let s:CheckStylePlugin = {} "{{{ checkStylePlugin
function! s:CheckStylePlugin.New()
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^\[INFO\] Starting audit...')
    return this
endfunction
function! s:CheckStylePlugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}

    let l:errorFinish = match(self._mvnOutputList, '^Audit done.',
        \ self._currentLine)
    let l:quickfixList = []
    if l:errorFinish > -1 
        let l:lineNo = self._currentLine
        while l:lineNo < l:errorFinish             
            let l:line = self._mvnOutputList[l:lineNo]
            try
                let l:posStart = 0        
                let l:posEnd = match(l:line, ':')
                let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ':', l:posStart)
                let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)

                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ':', l:posStart)
                let l:errorColNo = ''
                if l:posEnd > -1 
                    let l:errorColNo = strpart(l:line, l:posStart, 
                            \l:posEnd-l:posStart)
                    let l:posStart = l:posEnd + 1
                endif

                let l:message = strpart(l:line, l:posStart + 1)

                let l:fixList = {'bufnr': '', 'filename': l:filename, 
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixList)

            catch /notErrorLine/
                let l:exception=1
            endtry
            let l:lineNo += 1
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:lineNo
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction "}}} processErrors }}} checkStylePlugin

"{{{ pluginListInit
function! MvnPluginInit()
    let s:plugins = []
    for plugin in g:mvn_pluginList
        call add(s:plugins, eval("s:".plugin).New())
    endfor
    return s:plugins
endfunction; 
function! MvnPluginOutputInit(pluginList, mvnOutputList)
    for plugin in a:pluginList
        call plugin.setOutputList(a:mvnOutputList)
    endfor
endfunction; 
"}}} pluginListInit
"}}} mavenOutputProcessorPlugins

function! MvnCompile() "{{{
"Full project compilation with maven.
"   Don't use standard quickfix functionality - maven output seems 
"   challenging for vim builtin error formatting, so implement explicit 
"   invocation of compile, processing of output messages and 
"   build of quickfix list.

    call setqflist([]) 
    let l:outfile = s:mvn_tmpdir."/mvn.out"
    call delete(l:outfile)
    "surefire.useFile=false - force junit output to the console.
    let l:cmd = "mvn clean install -Dsurefire.useFile=false"
    let l:cmd = "mvn clean ".
    \"org.apache.maven.plugins:maven-compiler-plugin:".
    \g:mvn_compilerVersion.":compile install -Dsurefire.useFile=false"

    if strlen(v:servername) == 0
        let l:cmd = "!".l:cmd
        let l:cmd .=" | tee ".l:outfile
        exec l:cmd
        call MvnOP2QuickfixList(l:outfile)
    else 
        let l:Fn = function("MvnOP2QuickfixList")
        call asynccommand#run(l:cmd, l:Fn) 
    endif
endfunction; "}}}

function! MvnOP2QuickfixList(outputFile) "{{{
    let l:mvnOutput = readfile(a:outputFile)
    let l:outSize = len(l:mvnOutput)
    if l:outSize == 0
        throw "No Maven compile output."
    endif
    let l:quickfixList = MvnCompileProcessOutput(l:mvnOutput)
    if len(l:quickfixList) > 0 
        "fix from the last error in a file to the first error so the line numbers
        "are not contaminated.
        call reverse(l:quickfixList)
        call setqflist(l:quickfixList) 
        "call feedkeys(":cc \<CR>")
        call feedkeys(":cope \<CR>")
    endif
endfunction; "}}}

function! MvnCompileProcessOutput(mvnOutput) "{{{
"Process the output of the maven command, contained in the mvnOutput list.
"   Iterate each line of the output list and process with plugin list.
"   If a plugin is able to process a line it takes over processing of the 
"   mvnOutput list and iterates the list itself until processing of the 
"   plugin specific message is completed. When the plugin can process the 
"   mvnOutput list no further it returns control with the last line number 
"   ie  where it's processing completed to allow processing to continue
"   by another plugin. 
"a:mvnOutput - the output of the mvn command contained in a list.
"return - a quickfixList.
    let l:outSize = len(a:mvnOutput)
    call MvnPluginOutputInit(s:plugins, a:mvnOutput)
    let l:quickfixList = []
    let l:lineNo = 0
    while l:lineNo < l:outSize
        for plugin in s:plugins
            let processResult = plugin.processAtLine(l:lineNo)
            if processResult.lineNumber != l:lineNo
                let l:lineNo = processResult.lineNumber
                if len(processResult.quickfixList) > 0
                    call extend(l:quickfixList, processResult.quickfixList)
                endif
                continue
            endif
        endfor
        let l:lineNo += 1
    endwhile
    return l:quickfixList
endfunction; "}}}

function! MvnJavacCompile() "{{{
"Allow for quick single file compilation with javac.
    compiler javac_ex
    let l:envList = MvnTweakEnvForSrc(expand('%:p'))
    if empty(l:envList)
        return -1
    endif
    let l:target = l:envList[1]
    let l:classpath = l:envList[0]
    
    let &makeprg="javac  -g -d " . l:target . " -cp " . l:classpath . "  %"
    if strlen(v:servername) == 0
        make
    else
        "background execution of compile.
        call asynccommand#run(&makeprg, asynchandler#quickfix(&errorformat, ""))
    endif
endfunction; "}}}

function! MvnTweakEnvForSrc(srcFile) "{{{
"Set the environment variables relative to source file ie main/test.
"a:srcFile - the src file to set the env for. 
"return list [runClassPath, targetDir, sourcePath, isTest, path]
"   runClassPath - the runtime runClassPath
"   targetDir- the path to build target dir.
"   sourcePath - the path of the source files.
"   isTest - 1/0 the file is/isn't test source.
" Note: refactor to a map asap. 
    let l:targetDir= ""
    let l:runClassPath = g:vjde_lib_path
    let l:envList = []
    let l:sourcePath = g:mvn_javaSourcePath
    let l:isTest = 0
    if match(a:srcFile, s:mvn_projectMainSrc) > 0 
        let l:targetDir= g:mvn_projectHome."/".s:mvn_projectMainClasses
        let l:resourceDir = g:mvn_projectHome."/".s:mvn_projectMainResources
        if isdirectory(l:resourceDir)
            let l:runClassPath .= l:resourceDir.":".l:runClassPath
        endif
    elseif match(a:srcFile, s:mvn_projectTestSrc) > 0 
        let l:targetDir= g:mvn_projectHome."/".s:mvn_projectTestClasses
        let l:runClassPath = g:mvn_projectHome."/".s:mvn_projectTestClasses.":".l:runClassPath
        let l:resourceDir = g:mvn_projectHome."/".s:mvn_projectTestResources
        let l:sourcePath = g:mvn_projectHome."/".s:mvn_projectTestSrc.":".l:sourcePath
        if isdirectory(l:resourceDir)
            let l:runClassPath .= l:resourceDir.":".l:runClassPath
        endif
        let l:isTest = 1
    else
        echo "Could not identify maven target directory / run classpath."
        return -1
    endif

    call add(l:envList, l:runClassPath) 
    call add(l:envList, l:targetDir) 
    call add(l:envList, l:sourcePath) 
    call add(l:envList, l:isTest) 
    return l:envList
endfunction; "}}}
"}}} Compiler -----------------------------------------------------------------

"{{{ Debugging ----------------------------------------------------------------
function! MvnDoDebug() "{{{
"<F3> Run
"<C-F5> Run Application
"<F5> Continue Execution
"<F7> Step Into a Function
"<F8> Next Instruction
"<F9> Set Breakpoint
"<F10> Print variable value under cursor

"   let g:jdbcmd = "jdb -classpath ./target/classes -sourcepath ./src/main/java com.encompass.App" 
"   let l:debugger = "yavdb -s " . v:servername . " -t jdb \"" .  g:jdbcmd . "\""
"   let l:debugger = '!xterm \"yavdb -s DEBUG -t jdb\"'

" jdb -sourcepath -attach 11550 
    if strlen(v:servername) == 0
        echo "No servername!"
    else

        "Prompt for the debug port number.
        let l:debugSelectionList=[]
        let l:firstOption = "0: Run and debug current file port:"
        let l:firstOption .= g:mvn_debugPortList[0]
        call add(l:debugSelectionList, l:firstOption)

        let l:count = 1
        for port in g:mvn_debugPortList
            call add(l:debugSelectionList, l:count . ") connect to " . port .".")
            let l:count += 1
        endfor

        call inputsave()
        let l:SelectedOption= inputlist(l:debugSelectionList)
        call inputrestore()

        if l:SelectedOption == -1 || l:SelectedOption > len(l:debugSelectionList)
            return
        endif

        "setup the env for test/main debug.
        let l:envList = MvnTweakEnvForSrc(expand('%:p'))
        if empty(l:envList)
            return -1
        endif
        let l:sourcepath = l:envList[2]

        if l:SelectedOption == 0 
            let l:port= g:mvn_debugPortList[0]
            call MvnRunDebugProcess(l:port, l:envList)
        else
            let l:port= g:mvn_debugPortList[l:SelectedOption-1]
        endif

        "Execute the debugger.
        let l:debugger = "!xterm -T yavdb -e ".s:mvn_scriptDir."/bin/yavdb.sh "
        let l:debugger .= v:servername . " " . l:sourcepath ." " . l:port
        let l:debugger.= " |tee ".s:mvn_tmpdir."/dbgjdb.out &"
        exec l:debugger
    endif
endfunction; "}}}

function! MvnRunDebugProcess(port, envList) "{{{
    let l:classpath = a:envList[0]
    let l:sourcepath = a:envList[2]
    let l:isTest = a:envList[3]
    let l:classUnderDebug = MvnGetClassFromFilename(expand('%:p'))
    let l:output=""
    
    "Execute the java class or test runner.
    let l:javaProg = "!xterm  -T ".l:classUnderDebug
    let l:javaProg .= " -e ".s:mvn_scriptDir."/bin/run.sh "
    let l:javaProg .= " \"java -Xdebug -Xrunjdwp:transport=dt_socket"
    let l:javaProg .= ",address=".a:port.",server=y,suspend=y"
    if l:isTest
        let l:javaProg .= MvnGetJunitCmdString(l:classpath, l:classUnderDebug)
    else
        let l:javaProg .= " -classpath ".l:classpath
        let l:javaProg .= " ".l:classUnderDebug
    endif
    let l:javaProg .= "\" &"
    exec l:javaProg
endfunction; "}}}

function! MvnGetClassFromFilename(absoluteFilename) "{{{
"From the absolute java source file name determine the package class name.
    let l:srcFile = a:absoluteFilename
    let l:pos = matchend(l:srcFile, s:mvn_projectMainSrc.'/')
    if l:pos == -1
        let l:pos = matchend(l:srcFile, s:mvn_projectTestSrc.'/')
    endif
    if l:pos == -1
        echo "Error - No class." 
        return ""
    endif
    let l:className = strpart(l:srcFile, l:pos)
    let l:pos = match(l:className, '.java$')
    if l:pos == -1
        echo "Error - No class." 
        return ""
    endif
    let l:className = strpart(l:className, 0, l:pos)
    let l:className = substitute(l:className, '/', '.', 'g')
    return l:className
endfunction; "}}}
"}}} Debugging ----------------------------------------------------------------

"{{{ Javadoc/Sources ----------------------------------------------------------
function! MvnDownloadJavadoc() "{{{
"Download the javadoc using maven
    let l:cmd = "mvn org.apache.maven.plugins:"
    let l:cmd .= "maven-dependency-plugin:2.1:"
    let l:cmd .= "resolve -Dclassifier=javadoc"
    echo system(l:cmd)
endfunction; "}}}

function! MvnDownloadJavaSource() "{{{
"Download the dependency source using maven
    let l:cmd = "mvn org.apache.maven.plugins:"
    let l:cmd .= "maven-dependency-plugin:2.1:"
    let l:cmd .= "sources"
    echo system(l:cmd)
endfunction; "}}}

function! MvnOpenJavaDoc(javadocPath) "{{{
"Find the class under the cursor, locate the javadoc and open the html file with
"  lynx.
"javadocPath - the path to search for the documentation file.
"{{{ body
    call VjdeFindClassUnderCursor()
    let l:classname = g:vjde_java_cfu.class.name
    let l:classname= substitute(l:classname, "\\.", "/", "g") 
    let l:docfile = l:classname  . ".html" 
    echo l:docfile
    let l:tmpsuffixes = &suffixesadd
    set suffixesadd="html"
    let l:javadocPathList = split(a:javadocPath, ":")
    for tmpPath in l:javadocPathList
        let l:javadocfile = findfile(l:docfile, tmpPath)
        if strlen(l:javadocfile) > 0 
            break
        endif
    endfor
    set suffixesadd=l:tmpsuffixes
    exec "!lynx ". l:javadocfile
endfunction; "}}} body }}}

function! MvnInstallArtifactByClassifier(artifactPathParent, classJarLibPath, artifactType) "{{{
"Take the path to class jars and locate the associated artifact jars.
"Unpack the artifact jar for the class jars(if they exist) in the artifactPathParent.
"If the artifact is already unpacked then do nothing.
"artifactPathParent - the directory to contain the extracted artifacts, hopefully
"  one for each class jar.
"classJarLibPath - the class path containing class jars for which the associated 
"  artifact type will be extracted.
"artifactType - javadoc or sources
"return - the directory list of the existing and newly extracted artifact jars.
"{{{ body
    let l:artifactJarList = MvnGetArtifactJarList(a:classJarLibPath, a:artifactType)
    let l:artifactDirList = MvnGetArtifactDirList(l:artifactJarList, a:artifactPathParent)
    let l:indx = 0
    let l:artifactPath = ""
    for dirname in l:artifactDirList
        if !isdirectory(dirname) 
            call mkdir(l:dirname, "p")
            let l:jar = get(l:artifactJarList, l:indx)  
            let l:unjarCmd = "cd " . l:dirname . "; jar -xvf " . l:jar
            call system(l:unjarCmd)
        endif   
        if strlen(l:artifactPath) > 0
            let l:artifactPath .= ":"   
        endif
        let l:artifactPath .= dirname 
        let l:indx += 1
    endfor
    return l:artifactPath
endfunction; "}}} body }}}

function! MvnGetArtifactJarList(jarClassLibPath, artifactType) "{{{ 
"Take a classpath of class jars and create a list of jars of the associated 
"  artifactType, if they exist.  
"jarClassLibPath - pass g:vjde_lib_path
"artifactType - ie sources, javadoc 
"return - a list of jars of the requested artifactType.
"{{{ body
"replaced by split   let l:binJarList = MvnGetListFromString(a:jarClassLibPath, ":")
    let l:binJarList = split(a:jarClassLibPath, ":")
    let l:indx = 0
    let l:artifactFileList= []
    for jar in l:binJarList
        if stridx(jar, ".jar") > 0
            let l:artifactFileName=  substitute(l:jar, ".jar$", "-".a:artifactType.".jar", "")
            let l:artifactFile = findfile(l:artifactFileName, "/")
            if strlen(l:artifactFile) > 0
                call add(l:artifactFileList, l:artifactFileName) 
            endif 
        endif 
        let l:indx += 1
    endfor
    return l:artifactFileList
endfunction; "}}} body }}}

function! MvnGetArtifactDirList(jarList, parentArtifactDir) "{{{
"For a list of artifact jars, create a list of the names of directories 
"  to extract them into.
"jarList - list of absolute names for artifact jars.
"parentArtifactDir - the parent directory of the extracted artifacts.
"return - list of absolute directories to extract the artifact into.
"{{{ body
    let l:dirList = []
    for jar in a:jarList
        let l:dirName = MvnGetArtifactDirName(l:jar)
        call add(l:dirList, a:parentArtifactDir . "/" . l:dirName)
    endfor
    return l:dirList
endfunction; "}}} body }}}

function! MvnGetArtifactDirName(jarFilename) "{{{
"For a jar file, create a simple directory name by stripping path and extension. 
"jarFilename - absolute filename of a javadoc/sources jar.
"return - a simple directory name.
"{{{ body 
    let l:jarName = matchstr(a:jarFilename, "[^/]\\+jar$")
    let l:jarDir = substitute(l:jarName, ".jar$", "", "")
    return l:jarDir
endfunction; "}}} body }}}

function! MvnFindInherits(superclass) "{{{
"Search each tag file for implementors of the superclass.
"{{{ body
    let l:lineno = 1
    let g:inherits = []
    for l:tagfile in split(&tags,',')
        "match inherits:superclass,cl  inherits:cl,superclass  etc
        "/inherits:\(Plunk\|.\+,Plunk\)\(,\|$\|\s\)
        let l:cmd = "grep 'inherits:\\(".a:superclass
        let l:cmd .= "\\|.\\+,".a:superclass."\\)\\(,\\|$\\|\\s\\)' ".l:tagfile
        "let l:cmd = "grep 'inherits:.*".a:superclass.".*$' ". l:tagfile
        let l:tagMatches = system(l:cmd)
        if strlen(l:tagMatches) > 0 
            for l:line in split(l:tagMatches, "\n")
                call add(g:inherits, l:lineno.":".l:line)  
                let l:lineno += 1
            endfor
        endif
    endfor
    call MvnPickInherits()
endfunction; "}}} body }}}

function! MvnPickInherits()  "{{{
"Show the list of subclasses from the MvnFindInherits search.
"{{{ body
    if len(g:inherits) > 0
        call inputsave()
        let l:lineNo = inputlist(g:inherits)
        call inputrestore()
        if l:lineNo > 0 
            let l:itag = g:inherits[l:lineNo-1]
            let l:startPos = match(l:itag, ':') + 1
            let l:endPos = match(l:itag, '\s')
            let l:etag = strpart(l:itag, l:startPos, l:endPos - l:startPos)
            call feedkeys(":tag ".l:etag." \<CR>")
        endif
    else
        echo "No subclass found."
    endif
endfunction; "}}} body }}}

function! MvnGetTagFileDir(srcPath, mvn_projectHome) "{{{
"For each dir in the path build the tags.
"{{{ body
    let l:tmpDir = ""
    "let l:pos = match(a:srcPath, s:mvn_projectMainSrc)
    "if l:pos == -1  
    "    let l:pos = match(a:srcPath, s:mvn_projectTestSrc)
    "endif
    let l:pos = matchend(a:srcPath, a:mvn_projectHome) + 1
    if l:pos > 0 
        let l:tmpDir = strpart(a:srcPath, 0, l:pos - 1) 
    else
        let l:tmpDir = a:srcPath
    endif 
    return l:tmpDir 
endfunction; "}}} body }}}

function! MvnBuildTags(srcPath, mvn_ProjectHome) "{{{
"For each dir in the path build the tags.
"{{{ body
    let l:tagPath = ""
    let l:done = []
    for dir in split(a:srcPath, ':')
        let l:skip = 0
        let l:tmpDir = MvnGetTagFileDir(dir, a:mvn_ProjectHome) 
        if index(l:done, l:tmpDir) > -1
            "only do maven project once ie src/main/java and src/test/java
            let l:skip = 1     
        else 
            call add(l:done, l:tmpDir)
        endif
                 
        if l:skip == 0
            let l:cmd = s:mvn_tagprg." --fields=+m+i --recurse=yes -f ".l:tmpDir
            let l:cmd .= "/tags ".l:tmpDir    
            call system(l:cmd)
            if strlen(l:tagPath) > 0
                let l:tagPath .= ","
            endif
            let l:tagPath .= l:tmpDir."/tags"
        endif
    endfor
    return l:tagPath
endfunction; "}}} body }}}

function! MvnTagCurrentFile() "{{{
"Build the tags for the current file and append to the tag file.
"{{{ body
    let l:srcDir = expand("%:p:h")
    if !exists("g:mvn_projectHome") || len(g:mvn_projectHome) == 0 
        throw "No g:mvn_projectHome."
    endif
    let l:tagDir = MvnGetTagFileDir(l:srcDir, g:mvn_projectHome)
    let l:tagFile = l:tagDir."/tags"
    if filewritable(l:tagFile)
        "Remove all existing tags for the file.
        let l:cleanCmd ="( echo \"g^".expand("%:p")
        let l:cleanCmd .="^d\" ; echo 'wq' ) | ex -s ".l:tagFile
        call system(l:cleanCmd)
    endif
    let l:cmd = s:mvn_tagprg." -a --fields=+m+i --recurse=yes -f ".l:tagFile
    let l:cmd .= " ".expand("%:p")
    call system(l:cmd)
endfunction; "}}} body }}}

function! MvnFindJavaClass() "{{{
"Find a class in the jars in the maven repo.
"{{{ body
    call inputsave()
    let l:pattern = input("Enter the class name:")
    call inputrestore()
    let l:jarFilesList = split(system("find ~/.m2 -name \"*.jar\""), "\n")
    let l:matches = ""
    for jar in l:jarFilesList
        let l:result = system("jar -tvf ".jar."|grep ".l:pattern)
        if strlen(l:result) > 0
             echo(jar.": ".l:result."\n") 
        endif 
    endfor
endfunction; "}}} body }}}
"}}} Javadoc/Sources ----------------------------------------------------------

"{{{ Junit --------------------------------------------------------------------
function! MvnGetJunitCmdString(classpath, testClass) "{{{
"Build the junit command string.
   return " -classpath ".a:classpath." junit.textui.TestRunner ". a:testClass
endfunction; "}}}

function! MvnRunJunit() "{{{
"Run test add errors to quickfix list.
"{{{ body
    let l:envList = MvnTweakEnvForSrc(expand('%:p'))
    if empty(l:envList)
        return -1
    endif
    let l:classpath = l:envList[0]
    let l:testClass = MvnGetClassFromFilename(expand('%:p'))
    if strlen(l:testClass) == 0
        return -1 
    endif
    let l:junitCmd = MvnGetJunitCmdString(l:classpath, l:testClass)
    let l:cmd = "!java ". l:junitCmd 
    let l:cmd = l:cmd." | tee ".s:mvn_tmpdir."/junit.out"
    exec l:cmd
    let l:testOutput = readfile(s:mvn_tmpdir."/junit.out")
    let l:ctr = 0
    let l:errorSize = len(l:testOutput)
    let l:quickfixList = []
    while l:ctr < l:errorSize
        let l:line = l:testOutput[l:ctr]
        let l:pos = matchend(l:line,'^\d\+) [^:]\+:')
        if l:pos > -1
            let l:errorMessage = strpart(l:line, l:pos)
            let l:ctr += 1
            if l:ctr < l:errorSize
                let l:line = l:testOutput[l:ctr]
                let l:pos = matchend(l:line, '^\s\+[^:]\+:')
                let l:line = strpart(l:line, l:pos)
                let l:pos = matchend(l:line, ')')
                let l:lineno = strpart(l:line, 0, l:pos)
                if match(l:lineno, '\d+')
                    let l:qfixLine = {'lnum': l:lineno, 'bufnr': bufnr(""), 
                        \'col': 0, 'valid': 1, 'vcol': 1, 'nr': -1, 'type': 'E',
                        \'pattern': '', 'text': l:errorMessage } 
                    call add(l:quickfixList, l:qfixLine)
                endif
            endif
        endif 
        let l:ctr += 1
    endwhile
    if len(l:quickfixList) > 0
        call setqflist(l:quickfixList)
        cl 
    endif
endfunction; "}}} body }}}
"}}} Junit --------------------------------------------------------------------

"{{{ Tests --------------------------------------------------------------------
"{{{ TestRunnerObject ---------------------------------------------------------
let s:TestRunner = {}
function! s:TestRunner.New()
    let l:testRunner = copy(self)
    let l:testRunner.testCount = 0
    let l:testRunner.passCount = 0
    let l:testRunner.failCount = 0
    return l:testRunner
endfunction
function! s:TestRunner.AssertEquals(failMessage, expected, result)
    let self.testCount += 1
    if a:expected == a:result
        let self.passCount += 1
    else
        let self.failCount += 1
        let l:testResult = printf("%s",a:expected)." <> ".printf("%s",a:result)
        echo a:failMessage."\n\t".l:testResult
    endif
endfunction
function! s:TestRunner.PrintStats()
    let l:result = "Total Tests:".printf("%d",self.testCount)
    let l:result .= " Pass:".printf("%d",self.passCount)
    let l:result .= " Fail:".printf("%d",self.failCount)
    echo l:result
endfunction
"}}} TestRunnerObject ---------------------------------------------------------
function! s:TestPluginObj(testR) "{{{ TestPluginObj
"Test object operation.
    let l:jPlugin1 = s:JunitPlugin.New()
    call l:jPlugin1.addStartRegExp('reg1')
    let l:jPlugin2 = s:JunitPlugin.New()
    call l:jPlugin2.addStartRegExp('reg2')
    call a:testR.AssertEquals('TestPluginObj junit plugin fail:', 'reg1',
           \ get(l:jPlugin1._startRegExpList, 0))
    call a:testR.AssertEquals('TestPluginObj junit plugin fail:', 'reg2',
           \ get(l:jPlugin2._startRegExpList, 0))
endfunction "}}} TestPluginObj
function! s:TestMvn2Plugin(testR) "{{{ TestMvn2Plugin
    let l:maven2TestFile = s:mvn_scriptDir.'/plugin/test/maven2.out'
    let l:testList = readfile(l:maven2TestFile)
    let l:mvn2Plugin = s:Mvn2Plugin.New()
    call l:mvn2Plugin.setOutputList(l:testList)
    let l:errorsDict = l:mvn2Plugin.processAtLine(11)
    call a:testR.AssertEquals('mvn2 lineNumber in compiler output:', 20, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn2 Source file rowNum:', 39, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('mvn2 Source file colNum:', 0, l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('mvn2 Error message::', 'illegal start of type', l:errorsDict.quickfixList[0].text)
endfunction "}}} TestMvn2Plugin
function! s:TestMvn3Plugin(testR) "{{{ TestMvn3Plugin
    let l:maven3TestFile = s:mvn_scriptDir.'/plugin/test/maven3.out'
    let l:testList = readfile(l:maven3TestFile)
    let l:mvn3Plugin = s:Mvn3Plugin.New()
    call l:mvn3Plugin.setOutputList(l:testList)
    let l:errorsDict = l:mvn3Plugin.processAtLine(16)
    call a:testR.AssertEquals('mvn3 lineNumber in compiler output:', 19, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn3 Source file rowNum:', 9, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('mvn3 Source file colNum:', 1, l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('mvn3 Error message::', '<identifier> expected', l:errorsDict.quickfixList[0].text)
    let l:errorsDict = l:mvn3Plugin.processAtLine(17)
    call a:testR.AssertEquals('mvn3 lineNumber in compiler output:', 17, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn3 quickfix list size:', 0, len(l:errorsDict.quickfixList))
endfunction "}}} TestMvn3Plugin
function! s:TestJunitPlugin(testR) "{{{ TestJunitPlugin
    let l:testFile = s:mvn_scriptDir.'/plugin/test/maven3junit3.out'
    let l:testList = readfile(l:testFile)
    let l:junit3Plugin = s:Junit3Plugin.New()
    call l:junit3Plugin.setOutputList(l:testList)
    let l:errorsDict = l:junit3Plugin.processAtLine(35)
    call a:testR.AssertEquals('junit3 lineNumber :', 69, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('junit3 error count:', 3, len(l:errorsDict.quickfixList))
    call a:testR.AssertEquals('junit3 Source file rowNum:', 35, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('junit3 Source file colNum:', '', l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('junit3 Error message::', 'java.lang.ArithmeticException: / by zero', l:errorsDict.quickfixList[0].text)
endfunction "}}} TestJunitPlugin
function! s:TestCheckStylePlugin(testR) "{{{ TestCheckStylePlugin
    let l:checkStyleTestFile = s:mvn_scriptDir.'/plugin/test/checkstyle.out'
    let l:testList = readfile(l:checkStyleTestFile)
    let l:checkStylePlugin = s:CheckStylePlugin.New()
    call l:checkStylePlugin.setOutputList(l:testList)
    let l:errorsDict = l:checkStylePlugin.processAtLine(44)
    call a:testR.AssertEquals('checkstyle lineNumber in compiler output:', 110, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('checkstyle Source file rowNum:', 37, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('checkstyle Source file colNum:', 37, l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('checkstyle Error message::', 'Variable ''consecutiveCount'' should be declared final.', l:errorsDict.quickfixList[0].text)
    let l:checkStyleTestFile = s:mvn_scriptDir.'/plugin/test/checkstyle1.out'
    let l:testList = readfile(l:checkStyleTestFile)
    call l:checkStylePlugin.setOutputList(l:testList)
    let l:errorsDict = l:checkStylePlugin.processAtLine(47)
    call a:testR.AssertEquals('checkstyle lineNumber in compiler output:', 48, l:errorsDict.lineNumber)
endfunction "}}} TestCheckStylePlugin
function! s:TestProjTreeBuild(testR) "{{{ TestProjTreeBuild
    let l:prjLocation= s:mvn_scriptDir.'/plugin/test/proj'
    let l:pomList = [l:prjLocation.'/test/pom.xml']
    let l:result = MvnBuildProjectTree(l:pomList)
    call a:testR.AssertEquals('TestProjTreeBuild ::', 1, has_key(l:result.prjIdPath, "test:test:1.0"))

    let l:pomList = [l:prjLocation.'/parent/pom.xml',
    \ l:prjLocation.'/parent/test1/pom.xml',
    \ l:prjLocation.'/parent/test2/pom.xml',
    \ l:prjLocation.'/parent/test3/pom.xml']
    let l:result = MvnBuildProjectTree(l:pomList)
    "call writefile(l:result.prjTreeTxt, '/tmp/mvn.txt')
endfunction "}}} TestProjTreeBuild
function! s:TestMvnIsInList(testR) "{{{ TestMvnIsInList
"Test object operation. 
    let l:ret = MvnIsInList(['a', 'b', 'c'], "a")
    call a:testR.AssertEquals('MvnIsInList1: ', 1, l:ret)
    let l:ret = MvnIsInList(['a', 'b', 'c'], "d")
    call a:testR.AssertEquals('MvnIsInList2: ', 0, l:ret)
endfunction "}}} TestMvnIsInList
function! MvnRunTests() "{{{ MvnRunTests
    let l:testR = s:TestRunner.New()
    "{{{ misc tests
    call s:TestMvnIsInList(l:testR)
    "}}} misc tests
    "{{{ plugin tests
    call s:TestPluginObj(l:testR)
    call s:TestMvn2Plugin(l:testR)
    call s:TestMvn3Plugin(l:testR)
    call s:TestCheckStylePlugin(l:testR)
    call s:TestJunitPlugin(l:testR)
    "}}} plugin tests
    "{{{ Tree Build
    call s:TestProjTreeBuild(testR)
    "}}} Tree Build
    "{{{ MvnGetClassFromFilename
    let l:result = MvnGetClassFromFilename("/opt/proj/src/main/java/pack/age/Dummy.java")
    call l:testR.AssertEquals('MvnTweakEnvForSrc fail:', "pack.age.Dummy", l:result)
    "}}} MvnGetClassFromFilename
    call l:testR.PrintStats()
endfunction; "}}} MvnRunTests
"}}} Tests --------------------------------------------------------------------

"{{{ Key mappings -------------------------------------------------------------
map \rm :call MvnCompile() <RETURN>
map \rj :call MvnJavacCompile() <RETURN>
map \rd :call MvnDoDebug() <RETURN>
map \rt :call MvnRunJunit() <RETURN>
map \sd :call MvnOpenJavaDoc(g:mvn_javadocPath) <RETURN>
map \dd :call MvnDownloadJavadoc() <RETURN>
map \ds :call MvnDownloadJavaSource() <RETURN>
map \be :call MvnBuildEnvSelection() <RETURN>
map \bp :call MvnInsertProjectTree() <RETURN>
map \bt :call MvnTagCurrentFile() <RETURN>
map \fc :call MvnFindJavaClass() <RETURN>
map \gs :call MvnFindInherits(expand("<cword>")) <RETURN>
map \ps :call MvnPickInherits() <RETURN>
"}}} Key mappings -------------------------------------------------------------

"{{{ Public Variables ---------------------------------------------------------
set cfu=VjdeCompletionFun
"let g:vjde_lib_path = generated into in.vim
"let g:mvn_projectHome = generated into in.vim
"let g:mvn_javadocPath = generated into in.vim
"let g:mvn_javaSourcePath = generated into in.vim

if !exists('g:mvn_javadocParentDir')
    let g:mvn_javadocParentDir = "/opt/work/javadoc"
endif
if !exists('g:mvn_javaSourceParentDir')
    let g:mvn_javaSourceParentDir = "/opt/work/javasource"
endif
if !exists('g:mvn_additionalJavadocPath')
    let g:mvn_additionalJavadocPath = "/opt/work/javadoc/jdk-6u30-apidocs/api"
endif
if !exists('g:mvn_additionalJavaSourcePath')
    let g:mvn_additionalJavaSourcePath = "/opt/work/javasource/openjdk6-b24_4"
endif
if !exists('g:mvn_javaSrcFilterList')
    let g:mvn_javaSrcFilterList = ["*.java", "*.html", "*.js", "*.jsp"]
endif
if !exists('g:mvn_resourceFilterList')
    let g:mvn_resourceFilterList = ["*.vim", "*.xml", "*.properties", ".vjde"]
endif
if !exists('g:mvn_mavenType')
    let g:mvn_mavenType = "maven3"
endif
if !exists('g:mvn_debugPortList')
    let g:mvn_debugPortList = [8888,11550]
endif
if !exists('g:mvn_pluginList')
    let g:mvn_pluginList = ['Mvn3Plugin', 'Junit3Plugin', 'CheckStylePlugin'] 
endif
if !exists('g:mvn_compilerVersion')
    let g:mvn_compilerVersion = '2.5'
endif
"{{{ Private Variables --------------------------------------------------------
let s:mvn_projectMainSrc="src/main/java"
let s:mvn_projectTestSrc="src/test/java"
let s:mvn_projectMainClasses="target/classes"
let s:mvn_projectTestClasses="target/test-classes"
let s:mvn_projectMainResources="src/main/resources"
let s:mvn_projectTestResources="src/test/resources"
let s:mvn_projectMainWebapp="src/main/webapp"

let s:mvn_kernel = matchstr(system("uname -s"), '\w\+')
if s:mvn_kernel =~ "FreeBSD"
   let s:mvn_xpathcmd = "xpath filename \"query\""
   let s:mvn_tagprg = "exctags"
elseif s:mvn_kernel == "Linux"
   let s:mvn_xpathcmd = "xpath -e \"query\" filename"
   let s:mvn_tagprg = "ctags"
endif
let s:mvn_tmpdir = "/tmp"
let s:mvn_defaultProject = ""
let s:mvn_scriptFile = expand("<sfile>")
let s:mvn_scriptDir = strpart(s:mvn_scriptFile, 0, 
        \ match(s:mvn_scriptFile, "/plugin/")) 
let s:plugins = MvnPluginInit()
"}}} Private Variables  -------------------------------------------------------
"}}} Public Variables ---------------------------------------------------------
 
"vim:ts=4 sw=4 expandtab tw=78 ft=vim fdm=marker:
