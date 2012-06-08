vim-maven-ide
=============

A maven plugin for vim.

Features include:
* Project tree for file navigation and environment context management.
* Quickfix for output of maven plugins compile,junit,checkstyle. 
* Optional single source file compilation directly with javac.
* Compilation is background via AsyncCommand.
* Debug using yavdb, allows debug of class main or attach to jvm debug port.
* Junit run/quickfix/debug.                   
* Dependency source file and javadoc integration. Javadoc viewing uses lynx.                                       
* Exctags tag navigation. 
* Auto generation of project environment ie classpath, tag files.
* Dependency management for maven parent/child/sibling projects extracted from project poms.                          
* Autocomplete on methods, auto add of imports etc is via the vjde plugin project.

See doc/maven-ide.txt for more detail.