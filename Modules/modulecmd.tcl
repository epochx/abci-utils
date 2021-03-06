#!/usr/bin/tclsh
#
# MODULECMD.TCL, a pure TCL implementation of the module command
# Copyright (C) 2002-2004 Mark Lakata
# Copyright (C) 2004-2017 Kent Mein
# Copyright (C) 2016-2018 Xavier Delaruelle
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

##########################################################################

#
# Some Global Variables.....
#
set g_debug 0 ;# Set to 1 to enable debugging
set error_count 0 ;# Start with 0 errors
set g_return_false 0 ;# False value is rendered if == 1
set g_autoInit 0
set g_inhibit_interp 0 ;# Modulefile interpretation disabled if == 1
set g_inhibit_errreport 0 ;# Non-critical error reporting disabled if == 1
set g_inhibit_dispreport 0 ;# Display-mode reporting disabled if == 1
set g_force 0 ;# Path element reference counting if == 0
set CSH_LIMIT 4000 ;# Workaround for commandline limits in csh
set flag_default_dir 1 ;# Report default directories
set flag_default_mf 1 ;# Report default modulefiles and version alias
set reportfd "stderr" ;# File descriptor to use to report messages

set g_pager "/usr/bin/less" ;# Default command to page into, empty=disable
set g_pager_opts "-eFKRX" ;# Options to pass to the pager command

set g_siteconfig "/usr/share/Modules/etc/siteconfig.tcl" ;# Site configuration

# Used to tell if a machine is running Windows or not
proc isWin {} {
   return [expr {$::tcl_platform(platform) eq "windows"}]
}

# Get default path separator
proc getPathSeparator {} {
   if {![info exists ::g_def_separator]} {
      if {[isWin]} {
         set ::g_def_separator ";"
      } else {
         set ::g_def_separator ":"
      }
   }

   return $::g_def_separator
}

# Detect if terminal is attached to stderr message channel
proc isStderrTty {} {
   if {![info exists ::g_is_stderr_tty]} {
      set ::g_is_stderr_tty [expr {![catch {fconfigure stderr -mode}]}]
   }

   return $::g_is_stderr_tty
}

# Provide columns number for output formatting
proc getTtyColumns {} {
   if {![info exists ::g_tty_columns]} {
      # determine col number from tty capabilites
      # tty info query depends on running OS
      switch -- $::tcl_platform(os) {
         {SunOS} {
            catch {regexp {columns = (\d+);} [exec stty] match cols} errMsg
         }
         {Windows NT} {
            catch {regexp {Columns:\s+(\d+)} [exec mode] match cols} errMsg
         }
         default {
            catch {set cols [lindex [exec stty size] 1]} errMsg
         }
      }
      # default size if tty cols cannot be found
      if {![info exists cols] || $cols eq "0"} {
         set ::g_tty_columns 80
      } else {
         set ::g_tty_columns $cols
      }
   }

   return $::g_tty_columns
}

# Use MODULECONTACT variable to set your support email address
if {[info exists env(MODULECONTACT)]} {
   set contact $env(MODULECONTACT)
} else {
   # Or change this to your support email address...
   set contact "root@localhost"
}

# Set some directories to ignore when looking for modules.
set ignoreDir(CVS) 1
set ignoreDir(RCS) 1
set ignoreDir(SCCS) 1
set ignoreDir(.svn) 1
set ignoreDir(.git) 1

set show_oneperline 0 ;# Gets set if you do module list/avail -t
set show_modtimes 0 ;# Gets set if you do module list/avail -l
set show_filter "" ;# Gets set if you do module avail -d or -L

proc raiseErrorCount {} {
   incr ::error_count
}

proc renderFalse {} {
   reportDebug "renderFalse: called."

   if {[info exists ::g_false_rendered]} {
      reportDebug "renderFalse: false already rendered"
   } elseif {[info exists ::g_shellType]} {
      # setup flag to render only once
      set ::g_false_rendered 1

      # render a false value most of the time through a variable assignement
      # that will be looked at in the shell module function calling
      # modulecmd.tcl to return in turns a boolean status. Except for python
      # and cmake, the value assigned to variable is also returned as the
      # entire rendering status
      switch -- $::g_shellType {
         {sh} - {csh} - {fish} {
            # no need to set a variable on real shells as last statement
            # result can easily be checked
            puts stdout "test 0 = 1;"
         }
         {tcl} {
            puts stdout "set _mlstatus 0;"
         }
         {cmd} {
            puts stdout "set errorlevel=1"
         }
         {perl} {
            puts stdout "\$_mlstatus = 0;"
         }
         {python} {
            puts stdout "_mlstatus = False"
         }
         {ruby} {
            puts stdout "_mlstatus = false"
         }
         {lisp} {
            puts stdout "nil"
         }
         {cmake} {
            puts stdout "set(_mlstatus FALSE)"
         }
         {r} {
            puts stdout "mlstatus <- FALSE"
         }
      }
   }
}

proc renderTrue {} {
   reportDebug "renderTrue: called."

   # render a true value most of the time through a variable assignement that
   # will be looked at in the shell module function calling modulecmd.tcl to
   # return in turns a boolean status. Except for python and cmake, the
   # value assigned to variable is also returned as the full rendering status
   switch -- $::g_shellType {
      {sh} - {csh} - {fish} {
         # no need to set a variable on real shells as last statement
         # result can easily be checked
         puts stdout "test 0;"
      }
      {tcl} {
         puts stdout "set _mlstatus 1;"
      }
      {cmd} {
         puts stdout "set errorlevel=0"
      }
      {perl} {
         puts stdout "\$_mlstatus = 1;"
      }
      {python} {
         puts stdout "_mlstatus = True"
      }
      {ruby} {
         puts stdout "_mlstatus = true"
      }
      {lisp} {
         puts stdout "t"
      }
      {cmake} {
         puts stdout "set(_mlstatus TRUE)"
      }
      {r} {
         puts stdout "mlstatus <- TRUE"
      }
   }
}

proc renderText {text} {
   reportDebug "renderText: called ($text)."

   # render a text value most of the time through a variable assignement that
   # will be looked at in the shell module function calling modulecmd.tcl to
   # return in turns a string value.
   switch -- $::g_shellType {
      {sh} - {csh} - {fish} {
         foreach word $text {
            # no need to set a variable on real shells, echoing text will make
            # it available as result
            puts stdout "echo '$word';"
         }
      }
      {tcl} {
         puts stdout "set _mlstatus \"$text\";"
      }
      {cmd} {
         foreach word $text {
            puts stdout "echo $word"
         }
      }
      {perl} {
         puts stdout "\$_mlstatus = '$text';"
      }
      {python} {
         puts stdout "_mlstatus = '$text'"
      }
      {ruby} {
         puts stdout "_mlstatus = '$text'"
      }
      {lisp} {
         puts stdout "(message \"$text\")"
      }
      {cmake} {
         puts stdout "set(_mlstatus \"$text\")"
      }
      {r} {
         puts stdout "mlstatus <- '$text'"
      }
   }
}

#
# Debug, Info, Warnings and Error message handling.
#

# save message when report is not currently initialized as we do not
# know yet if debug mode is enabled or not
proc reportDebug {message {nonewline ""}} {
   lappend ::errreport_buffer [list "reportDebug" $message $nonewline]
}

# regular procedure to use once error report is initialized
proc __reportDebug {message {nonewline ""}} {
   if {$::g_debug} {
      report "DEBUG $message" "$nonewline"
   }
}

proc reportWarning {message {nonewline ""}} {
   if {!$::g_inhibit_errreport} {
      report "WARNING: $message" "$nonewline"
   }
}

proc reportError {message {nonewline ""}} {
   # if report disabled, also disable error raise to get a coherent
   # behavior (if no message printed, no error code change)
   if {!$::g_inhibit_errreport} {
      raiseErrorCount
      report "ERROR: $message" "$nonewline"
   }
}

# save message if report is not yet initialized
proc reportErrorAndExit {message} {
   lappend ::errreport_buffer [list "reportErrorAndExit" $message]
}

# regular procedure to use once error report is initialized
proc __reportErrorAndExit {message} {
   raiseErrorCount
   renderFalse
   error "$message"
}

proc reportInternalBug {message modfile} {
   # if report disabled, also disable error raise to get a coherent
   # behavior (if no message printed, no error code change)
   if {!$::g_inhibit_errreport} {
      raiseErrorCount
      report "Module ERROR: $message\n  In '$modfile'\n  Please contact\
         <$::contact>"
   }
}

# save message if report is not yet initialized
proc report {message {nonewline ""}} {
   lappend ::errreport_buffer [list "report" $message $nonewline]
}

# regular procedure to use once error report is initialized
proc __report {message {nonewline ""}} {
   # start pager at first call and only if enabled
   if {$::start_pager} {
      set ::start_pager 0
      startPager
   }

   # protect from issue with fd, just ignore it
   catch {
      if {$nonewline ne ""} {
         puts -nonewline $::reportfd "$message"
      } else {
         puts $::reportfd "$message"
      }
   }
}

# report error the correct way depending of its type
proc reportIssue {issuetype issuemsg {issuefile {}}} {
   switch -- $issuetype {
      {invalid} {
         reportInternalBug $issuemsg $issuefile
      }
      default {
         reportError $issuemsg
      }
   }
}

proc reportVersion {} {
   report "Modules Release 4.1.4\
      (2018-08-20)"
}

# disable error reporting (non-critical report only) unless debug enabled
proc inhibitErrorReport {} {
   if {!$::g_debug} {
      set ::g_inhibit_errreport 1
   }
}

proc reenableErrorReport {} {
   set ::g_inhibit_errreport 0
}

proc isErrorReportInhibited {} {
   return $::g_inhibit_errreport
}

# init error report and output buffered messages
proc initErrorReport {} {
   # determine message paging configuration and enablement
   initPager

   # replace report procedures used to bufferize messages until error report
   # being initialized by regular report procedures
   rename ::reportDebug {}
   rename ::__reportDebug ::reportDebug
   rename ::reportErrorAndExit {}
   rename ::__reportErrorAndExit ::reportErrorAndExit
   rename ::report {}
   rename ::__report ::report

   # now error report is init output every message saved in buffer
   foreach errreport $::errreport_buffer {
      eval $errreport
   }
}

# exit in a clean manner by closing interaction with external components
proc cleanupAndExit {code} {
   # close pager if enabled
   if {$::reportfd ne "stderr"} {
      catch {flush $::reportfd}
      catch {close $::reportfd}
   }

   exit $code
}

# init configuration for output paging to prepare for startup
proc initPager {} {
   # default pager enablement depends of pager command value
   if {$::g_pager eq "" || [file tail $::g_pager] eq "cat"} {
      set use_pager 0
      set init_use_pager 0
   } else {
      set use_pager 1
      set init_use_pager 1
   }

   if {[info exists ::env(MODULES_PAGER)]} {
      if {$::env(MODULES_PAGER) ne ""} {
         # MODULES_PAGER env variable set means pager should be enabled
         if {!$use_pager} {
            set use_pager 1
         }
         # fetch pager command and option
         set ::g_pager [lindex $::env(MODULES_PAGER) 0]
         set ::g_pager_opts [lrange $::env(MODULES_PAGER) 1 end]

      # variable defined empty means no-pager
      } else {
         set use_pager 0
         set ::g_pager ""
         set ::g_pager_opts ""
      }

      reportDebug "initPager: configure pager from MODULES_PAGER variable\
         (use_pager=$use_pager, cmd='$::g_pager', opts='$::g_pager_opts')"
   }

   # paging may have been enabled or disabled from the command-line
   if {[info exists ::asked_pager]} {
      # enable from command-line only if it is enabled in script config
      if {$::asked_pager && !$use_pager && $init_use_pager} {
         set use_pager 1
      } elseif {!$::asked_pager && $use_pager} {
         set use_pager 0
      }
      set asked $::asked_pager
   } else {
      set asked "-"
   }

   # empty or 'cat' pager command means no-pager
   if {$use_pager && ($::g_pager eq "" || [file tail $::g_pager] eq "cat")} {
      set use_pager 0
   }

   # start paging if enabled and if error stream is attached to a terminal
   set is_tty [isStderrTty]
   if {$is_tty && $use_pager} {
      reportDebug "initPager: start pager (asked_pager=$asked,\
         cmd='$::g_pager', opts='$::g_pager_opts')"
      set ::start_pager 1
   } else {
      reportDebug "initPager: no pager start (is_tty=$is_tty,\
         use_pager=$use_pager, asked_pager=$asked, cmd='$::g_pager',\
         opts='$::g_pager_opts')"
      set ::start_pager 0
   }
}

# start pager pipe process with defined configuration
proc startPager {} {
   if {[catch {
      set ::reportfd [open "|$::g_pager $::g_pager_opts >@stderr 2>@stderr" w]
      fconfigure $::reportfd -buffering line -blocking 1 -buffersize 65536
   } errMsg]} {
      reportWarning $errMsg
   }
}

########################################################################
# Use a slave TCL interpreter to execute modulefiles
#

proc unset-env {var} {
   if {[info exists ::env($var)]} {
      reportDebug "unset-env:  $var"
      unset ::env($var)
   }
}

proc execute-modulefile {modfile {must_have_cookie 1}} {
   pushModuleFile $modfile

   # skip modulefile if interpretation has been inhibited
   if {$::g_inhibit_interp} {
      reportDebug "execute-modulefile: Skipping $modfile"
      return 1
   }

   reportDebug "execute-modulefile:  Starting $modfile"

   if {![info exists ::g_modfileUntrackVars]} {
      # list variable that should not be tracked for saving
      array set ::g_modfileUntrackVars [list g_debug 1 g_inhibit_interp 1\
         g_inhibit_errreport 1 g_inhibit_dispreport 1\
         ModulesCurrentModulefile 1 must_have_cookie 1 modcontent 1 env 1]

      # commands that should be renamed before aliases setup
      array set ::g_modfileRenameCmds [list puts _puts]

      # list interpreter alias commands to define
      array set ::g_modfileAliases [list setenv setenv unsetenv unsetenv\
         getenv getenv system system chdir chdir append-path append-path\
         prepend-path prepend-path remove-path remove-path prereq prereq\
         conflict conflict is-loaded is-loaded is-saved is-saved is-used\
         is-used is-avail is-avail module module module-info\
         module-info module-whatis module-whatis set-alias set-alias\
         unset-alias unset-alias uname uname x-resource x-resource exit\
         exitModfileCmd module-version module-version module-alias\
         module-alias module-virtual module-virtual module-trace module-trace\
         module-verbosity module-verbosity module-user module-user module-log\
         module-log reportInternalBug reportInternalBug reportWarning\
         reportWarning reportError reportError raiseErrorCount\
         raiseErrorCount report report isWin isWin puts putsModfileCmd\
         readModuleContent readModuleContent]

      # alias commands where interpreter ref should be passed as argument
      array set ::g_modfileAliasesPassItrp [list puts 1]
   }

   # dedicate an interpreter per level of interpretation to have in case of
   # cascaded interpretations a specific interpreter per level
   set itrp "__modfile[info level]"

   # create modulefile interpreter at first interpretation
   if {![interp exists $itrp]} {
      interp create $itrp

      # dump initial interpreter state to restore it before each modulefile
      # interpreation
      dumpInterpState $itrp g_modfileVars g_modfileArrayVars\
         g_modfileUntrackVars g_modfileProcs

      # interp has just been created
      set fresh 1
   } else {
      set fresh 0
   }

   # reset interp state command before each interpretation
   resetInterpState $itrp $fresh g_modfileVars g_modfileArrayVars\
      g_modfileUntrackVars g_modfileProcs g_modfileAliases\
      g_modfileAliasesPassItrp g_modfileRenameCmds g_modfileCommands

   # reset modulefile-specific variable before each interpretation
   interp eval $itrp set ::ModulesCurrentModulefile $modfile
   interp eval $itrp set ::g_debug $::g_debug
   interp eval $itrp set ::g_inhibit_interp $::g_inhibit_interp
   interp eval $itrp set ::g_inhibit_errreport $::g_inhibit_errreport
   interp eval $itrp set ::g_inhibit_dispreport $::g_inhibit_dispreport
   interp eval $itrp set must_have_cookie $must_have_cookie

   set errorVal [interp eval $itrp {
      set modcontent [readModuleContent $::ModulesCurrentModulefile 1\
         $must_have_cookie]
      if {$modcontent eq ""} {
         return 1
      }
      info script $::ModulesCurrentModulefile
      # eval then call for specific proc depending mode under same catch
      set sourceFailed [catch {
         eval $modcontent
         switch -- [module-info mode] {
            {help} {
               if {[info procs "ModulesHelp"] eq "ModulesHelp"} {
                  ModulesHelp
               } else {
                  reportWarning "Unable to find ModulesHelp in\
                     $::ModulesCurrentModulefile."
               }
            }
            {display} {
               if {[info procs "ModulesDisplay"] eq "ModulesDisplay"} {
                  ModulesDisplay
               }
            }
            {test} {
               if {[info procs "ModulesTest"] eq "ModulesTest"} {
                  if {[string is true -strict [ModulesTest]]} {
                     report "Test result: PASS"
                  } else {
                     report "Test result: FAIL"
                     raiseErrorCount
                  }
               } else {
                  reportWarning "Unable to find ModulesTest in\
                     $::ModulesCurrentModulefile."
               }
            }
         }
      } errorMsg]
      if {$sourceFailed} {
         # no error in case of "continue" command
         # catch continue even if called outside of a loop
         if {$errorMsg eq "invoked \"continue\" outside of a loop"\
            || $sourceFailed == 4} {
            unset errorMsg
            return 0
         # catch break even if called outside of a loop
         } elseif {$errorMsg eq "invoked \"break\" outside of a loop"\
            || ($errorMsg eq "" && (![info exists ::errorInfo]\
            || $::errorInfo eq ""))} {
            raiseErrorCount
            unset errorMsg
            return 1
         } elseif {$errorMsg eq "SUB_FAILED"} {
            # error counter and message already handled, just return error
            return 1
         } elseif [regexp "^WARNING" $errorMsg] {
            raiseErrorCount
            report $errorMsg
            return 1
         } else {
            reportInternalBug $errorMsg $::ModulesCurrentModulefile
            return 1
         }
      } else {
         unset errorMsg
         return 0
      }
   }]

   popModuleFile

   reportDebug "Exiting $modfile"
   return $errorVal
}

# Smaller subset than main module load... This function runs modulerc and
# .version files
proc execute-modulerc {modfile} {
   reportDebug "execute-modulerc: $modfile"

   pushModuleFile $modfile
   set ::ModulesVersion {}
   # does not report commands from rc file on display mode
   set ::g_inhibit_dispreport 1

   set modname [file dirname [currentModuleName]]

   if {![info exists ::g_rcfilesSourced($modfile)]} {
      if {![info exists ::g_modrcUntrackVars]} {
         # list variable that should not be tracked for saving
         array set ::g_modrcUntrackVars [list g_debug 1 g_inhibit_errreport 1\
            g_inhibit_dispreport 1 ModulesCurrentModulefile 1\
            ModulesVersion 1 modcontent 1 env 1]

         # commands that should be renamed before aliases setup
         array set ::g_modrcRenameCmds [list]

         # list interpreter alias commands to define
         array set ::g_modrcAliases [list uname uname system system chdir\
            chdir module-version module-version module-alias module-alias\
            module-virtual module-virtual module module module-info\
            module-info module-trace module-trace module-verbosity\
            module-verbosity module-user module-user module-log module-log\
            reportInternalBug reportInternalBug setModulesVersion\
            setModulesVersion readModuleContent readModuleContent]

         # alias commands where interpreter ref should be passed as argument
         array set ::g_modrcAliasesPassItrp [list]
      }

      # dedicate an interpreter per level of interpretation to have in case of
      # cascaded interpretations a specific interpreter per level
      set itrp "__modrc[info level]"

      reportDebug "execute-modulerc: sourcing rc $modfile"
      # create modulerc interpreter at first interpretation
      if {![interp exists $itrp]} {
         interp create $itrp

         # dump initial interpreter state to restore it before each modulerc
         # interpreation
         dumpInterpState $itrp g_modrcVars g_modrcArrayVars\
            g_modrcUntrackVars g_modrcProcs

         # interp has just been created
         set fresh 1
      } else {
         set fresh 0
      }

      # reset interp state command before each interpretation
      resetInterpState $itrp $fresh g_modrcVars g_modrcArrayVars\
         g_modrcUntrackVars g_modrcProcs g_modrcAliases\
         g_modrcAliasesPassItrp g_modrcRenameCmds g_modrcCommands

      interp eval $itrp set ::ModulesCurrentModulefile $modfile
      interp eval $itrp set ::g_debug $::g_debug
      interp eval $itrp set ::g_inhibit_errreport $::g_inhibit_errreport
      interp eval $itrp set ::g_inhibit_dispreport $::g_inhibit_dispreport
      interp eval $itrp {set ::ModulesVersion {}}

      set errorVal [interp eval $itrp {
         set modcontent [readModuleContent $::ModulesCurrentModulefile]
         if {$modcontent eq ""} {
            # simply skip rc file, no exit on error here
            return 1
         }
         info script $::ModulesCurrentModulefile
         if [catch {eval $modcontent} errorMsg] {
            reportInternalBug $errorMsg $::ModulesCurrentModulefile
            return 1
         } else {
            # pass ModulesVersion value to master interp
            if {[info exists ::ModulesVersion]} {
               setModulesVersion $::ModulesVersion
            }
            return 0
         }
      }]

      # default version set via ModulesVersion variable in .version file
      # override previously defined default version for modname
      if {[file tail $modfile] eq ".version" && $::ModulesVersion ne ""} {
         # ModulesVersion should target an element in current directory
         if {[string first "/" $::ModulesVersion] == -1} {
            setModuleResolution "$modname/default" $modname/$::ModulesVersion\
               "default"
         } else {
            reportError "Invalid ModulesVersion '$::ModulesVersion' defined"
         }
      }

      # Keep track of rc files we already sourced so we don't run them again
      set ::g_rcfilesSourced($modfile) $::ModulesVersion
   }

   # re-enable command report on display mode
   set ::g_inhibit_dispreport 0

   popModuleFile

   return $::g_rcfilesSourced($modfile)
}

# Save list of the defined procedure and the global variables with their
# associated values set in slave interpreter passed as argument. Global
# structures are used to save these information and the name of these
# structures are provided as argument.
proc dumpInterpState {itrp dumpVarsVN dumpArrayVarsVN untrackVarsVN\
   dumpProcsVN} {
   upvar #0 $dumpVarsVN dumpVars
   upvar #0 $dumpArrayVarsVN dumpArrayVars
   upvar #0 $untrackVarsVN untrackVars
   upvar #0 $dumpProcsVN dumpProcs

   # save name and value for any other global variables
   foreach var [$itrp eval {info globals}] {
      if {![info exists untrackVars($var)]} {
         reportDebug "dumpInterpState: saving for $itrp var $var"
         if {[$itrp eval array exists ::$var]} {
            set dumpVars($var) [$itrp eval array get ::$var]
            set dumpArrayVars($var) 1
         } else {
            set dumpVars($var) [$itrp eval set ::$var]
         }
      }
   }

   # save name of every defined procedures
   foreach var [$itrp eval {info procs}] {
      set dumpProcs($var) 1
   }
   reportDebug "dumpInterpState: saving for $itrp proc list [array names\
      dumpProcs]"
}

# Restore initial setup of slave interpreter passed as argument based on
# global structure previously filled with initial list of defined procedure
# and values of global variable.
proc resetInterpState {itrp fresh dumpVarsVN dumpArrayVarsVN untrackVarsVN\
   dumpProcsVN aliasesVN aliasesPassItrpVN renameCmdsVN dumpCommandsVN} {
   upvar #0 $dumpVarsVN dumpVars
   upvar #0 $dumpArrayVarsVN dumpArrayVars
   upvar #0 $untrackVarsVN untrackVars
   upvar #0 $dumpProcsVN dumpProcs
   upvar #0 $aliasesVN aliases
   upvar #0 $aliasesPassItrpVN aliasesPassItrp
   upvar #0 $renameCmdsVN renameCmds
   upvar #0 $dumpCommandsVN dumpCommands

   # look at list of defined procedures and delete those not part of the
   # initial state list. do not check if they have been altered as no vital
   # procedures lied there. note that if a Tcl command has been overridden
   # by a proc, it will be removed here and command will also disappear
   foreach var [$itrp eval {info procs}] {
      if {![info exists dumpProcs($var)]} {
         reportDebug "resetInterpState: removing on $itrp proc $var"
         $itrp eval [list rename $var {}]
      }
   }

   # rename some commands on first time before aliases defined below
   # overwrite them
   if {$fresh} {
      foreach cmd [array names renameCmds] {
         $itrp eval rename $cmd $renameCmds($cmd)
      }
   }

   # set interpreter alias commands each time to guaranty them being
   # defined and not overridden by modulefile or modulerc content
   foreach alias [array names aliases] {
      if {[info exists aliasesPassItrp($alias)]} {
         interp alias $itrp $alias {} $aliases($alias) $itrp
      } else {
         interp alias $itrp $alias {} $aliases($alias)
      }
   }

   # dump interpreter command list here on first time as aliases should be
   # set prior to be found on this list for correct match
   if {![info exists dumpCommands]} {
      set dumpCommands [$itrp eval {info commands}]
      reportDebug "resetInterpState: saving for $itrp command list\
         $dumpCommands"
   # if current interpreter command list does not match initial list it
   # means that at least one command has been altered so we need to recreate
   # interpreter to guaranty proper functioning
   } elseif {$dumpCommands ne [$itrp eval {info commands}]} {
      reportDebug "resetInterpState: missing command(s), recreating $itrp"
      interp delete $itrp
      interp create $itrp
      # rename some commands and set aliases again on fresh interpreter
      foreach cmd [array names renameCmds] {
         $itrp eval rename $cmd $renameCmds($cmd)
      }
      foreach alias [array names aliases] {
         if {[info exists aliasesPassItrp($alias)]} {
            interp alias $itrp $alias {} $aliases($alias) $itrp
         } else {
            interp alias $itrp $alias {} $aliases($alias)
         }
      }
   }

   # check every global variables currently set and correct them to restore
   # initial interpreter state. work on variables at the very end to ensure
   # procedures and commands are correctly defined
   foreach var [$itrp eval {info globals}] {
      if {![info exists untrackVars($var)]} {
         if {![info exists dumpVars($var)]} {
            reportDebug "resetInterpState: removing on $itrp var $var"
            $itrp eval unset ::$var
         } elseif {![info exists dumpArrayVars($var)]} {
            if {$dumpVars($var) ne [$itrp eval set ::$var]} {
               reportDebug "resetInterpState: restoring on $itrp var $var"
               if {[llength $dumpVars($var)] > 1} {
                  # restore value as list
                  $itrp eval set ::$var [list $dumpVars($var)]
               } else {
                  $itrp eval set ::$var $dumpVars($var)
               }
            }
         } else {
            if {$dumpVars($var) ne [$itrp eval array get ::$var]} {
               reportDebug "resetInterpState: restoring on $itrp var $var"
               $itrp eval array set ::$var [list $dumpVars($var)]
            }
         }
      }
   }
}

########################################################################
# commands run from inside a module file
#

# Dummy procedures for commands available on C-version but not
# implemented here. These dummy procedures enables support for
# modulefiles using these commands while warning users these
# commands have no effect.
proc module-log {args} {
   reportWarning "'module-log' command not implemented"
}

proc module-verbosity {args} {
   reportWarning "'module-verbosity' command not implemented"
}

proc module-user {args} {
   reportWarning "'module-user' command not implemented"
}

proc module-trace {args} {
   reportWarning "'module-trace' command not implemented"
}

proc module-info {what {more {}}} {
   set mode [currentMode]

   reportDebug "module-info: $what $more  mode=$mode"

   switch -- $what {
      {mode} {
         if {$more ne ""} {
            set command [currentCommandName]
            return [expr {$mode eq $more || ($more eq "remove" && $mode eq \
               "unload") || ($more eq "switch" && $command eq "switch")}]
         } else {
            return $mode
         }
      }
      {command} {
         set command [currentCommandName]
         if {$more eq ""} {
            return $command
         } else {
            return [expr {$command eq $more}]
         }
      }
      {name} {
         return [currentModuleName]
      }
      {specified} {
         return [currentSpecifiedName]
      }
      {shell} {
         if {$more ne ""} {
            return [expr {$::g_shell eq $more}]
         } else {
            return $::g_shell
         }
      }
      {flags} {
         # C-version specific option, not relevant for Tcl-version but return
         # a zero integer value to avoid breaking modulefiles using it
         return 0
      }
      {shelltype} {
         if {$more ne ""} {
            return [expr {$::g_shellType eq $more}]
         } else {
            return $::g_shellType
         }
      }
      {user} {
         # C-version specific option, not relevant for Tcl-version but return
         # an empty value or false to avoid breaking modulefiles using it
         if {$more ne ""} {
            return 0
         } else {
            return {}
         }
      }
      {alias} {
         set ret [resolveModuleVersionOrAlias $more]
         if {$ret ne $more} {
            return $ret
         } else {
            return {}
         }
      }
      {trace} {
         return {}
      }
      {tracepat} {
         return {}
      }
      {type} {
         return "Tcl"
      }
      {symbols} {
         lassign [getModuleNameVersion $more 1] mod modname modversion
         set tag_list [getVersAliasList $mod]
         # if querying special symbol "default" but nothing found registered
         # on it, look at symbol registered on bare module name in case there
         # are symbols registered on it but no default symbol set yet to link
         # to them
         if {[llength $tag_list] == 0 && $modversion eq "default"} {
            set tag_list [getVersAliasList $modname]
         }
         return [join $tag_list ":"]
      }
      {version} {
         lassign [getModuleNameVersion $more 1] mod
         return [resolveModuleVersionOrAlias $mod]
      }
      {loaded} {
         lassign [getModuleNameVersion $more 1] mod
         return [getLoadedMatchingName $mod "returnall"]
      }
      default {
         error "module-info $what not supported"
         return {}
      }
   }
}

proc module-whatis {args} {
   set mode [currentMode]
   set message [join $args " "]

   reportDebug "module-whatis: $message  mode=$mode"

   if {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "module-whatis\t$message"
   }\
   elseif {$mode eq "whatis"} {
      lappend ::g_whatis $message
   }
   return {}
}

# convert environment variable references in string to their values
# every local variable is prefixed by '0' to ensure they will not be
# overwritten through variable reference resolution process
proc resolvStringWithEnv {0str} {
   # fetch variable references in string
   set 0match_list [regexp -all -inline {\$[{]?([A-Za-z_][A-Za-z0-9_]*)[}]?}\
      ${0str}]
   if {[llength ${0match_list}] > 0} {
      # put in local scope every environment variable referred in string
      for {set 0i 1} {${0i} < [llength ${0match_list}]} {incr 0i 2} {
         set 0varname [lindex ${0match_list} ${0i}]
         if {![info exists ${0varname}]} {
            if {[info exists ::env(${0varname})]} {
               set ${0varname} $::env(${0varname})
            } else {
               set ${0varname} ""
            }
         }
      }
      # resolv variable reference with values (now in local scope)
      set 0res [subst -nobackslashes -nocommands ${0str}]
   } else {
      set 0res ${0str}
   }

   reportDebug "resolvStringWithEnv: '${0str}' resolved to '${0res}'"

   return ${0res}
}

# deduce modulepath from modulefile and module name
proc getModulepathFromModuleName {modfile modname} {
   return [string range $modfile 0 end-[string length "/$modname"]]
}

# deduce module name from modulefile and modulepath
proc getModuleNameFromModulepath {modfile modpath} {
   return [string range $modfile [string length "$modpath/"] end]
}

# extract module name from modulefile and currently enabled modulepaths
proc findModuleNameFromModulefile {modfile} {
   set ret ""

   foreach modpath [getModulePathList] {
      if {[string first "$modpath/" "$modfile/"] == 0} {
         set ret [getModuleNameFromModulepath $modfile $modpath]
         break
      }
   }
   return $ret
}

# extract modulepath from modulefile and currently enabled modulepaths
proc findModulepathFromModulefile {modfile} {
   set ret ""

   foreach modpath [getModulePathList] {
      if {[string first "$modpath/" "$modfile/"] == 0} {
         set ret $modpath
         break
      }
   }
   return $ret
}

# Determine with a name provided as argument the corresponding module name,
# version and name/version. Module name is guessed from current module name
# when shorthand version notation is used. Both name and version are guessed
# from current module if name provided is empty. If 'name_relative_tocur' is
# enabled then name argument may be interpreted as a name relative to the
# current modulefile directory (useful for module-version and module-alias
# for instance).
proc getModuleNameVersion {{name {}} {name_relative_tocur 0}} {
   set curmod [currentModuleName]
   set curmodname [file dirname $curmod]
   set curmodversion [file tail $curmod]

   if {$name eq ""} {
      set name $curmodname
      set version $curmodversion
   # check for shorthand version notation like "/version" or "./version"
   # only if we are currently interpreting a modulefile or modulerc
   } elseif {$curmod ne "" && [regexp {^\.?\/(.*)$} $name match version]} {
      # if we cannot distinguish a module name, raise error when
      # shorthand version notation is used
      if {$::ModulesCurrentModulefile ne $curmod} {
         # name is the name of current module directory
         set name $curmodname
      } else {
         reportError "Invalid modulename '$name' found"
         return {}
      }
   } else {
      set name [string trimright $name "/"]
      set version [file tail $name]
      if {$name eq $version} {
         set version ""
      } else {
         set name [file dirname $name]
      }
      # name may correspond to last part of current module
      # if so name is replaced by current module name
      if {$name_relative_tocur && [file tail $curmodname] eq $name} {
         set name $curmodname
      }
   }

   if {$version eq ""} {
      set mod $name
   } else {
      set mod $name/$version
   }

   return [list $mod $name $version]
}

# Register alias or symbolic version deep resolution in a global array that
# can be used thereafter to get in one query the actual modulefile behind
# a virtual name. Also consolidate a global array that in the same manner
# list all the symbols held by modulefiles.
proc setModuleResolution {mod target {symver {}} {override_res_path 1}} {
   global g_moduleResolved g_resolvedHash g_resolvedPath g_symbolHash

   # find end-point module and register step-by-step path to get to it
   set res $target
   set res_path $res
   while {$mod ne $res && [info exists g_resolvedPath($res)]} {
      set res $g_resolvedPath($res)
      lappend res_path $res
   }

   # error if resolution end on initial module
   if {$mod eq $res} {
      reportError "Resolution loop on '$res' detected"
      return 0
   }

   # module name will be useful when registering symbol
   if {$symver ne ""} {
      lassign [getModuleNameVersion $mod] modfull modname
   }

   # change default symbol owner if previously given
   if {$symver eq "default"} {
      # alternative name "modname" is set when mod = "modname/default" both
      # names will be registered to be known for queries and resolution defs
      set modalt $modname

      if {[info exists g_moduleResolved($mod)]} {
         set prev $g_moduleResolved($mod)
         # no test needed, there must be a "default" in $prev symbol list
         set idx [lsearch -exact $g_symbolHash($prev) "default"]
         reportDebug "setModuleResolution: remove symbol 'default' from\
            '$prev'"
         set g_symbolHash($prev) [lreplace $g_symbolHash($prev) $idx $idx]
      }
   }

   # register end-point resolution
   reportDebug "setModuleResolution: $mod resolved to $res"
   set g_moduleResolved($mod) $res
   # set first element of resolution path only if not already set or
   # scratching enabled, no change when propagating symbol along res path
   if {$override_res_path || ![info exists g_resolvedPath($mod)]} {
      set g_resolvedPath($mod) $target
   }
   lappend g_resolvedHash($res) $mod

   # also register resolution on alternative name if any
   if {[info exists modalt]} {
      reportDebug "setModuleResolution: $modalt resolved to $res"
      set g_moduleResolved($modalt) $res
      if {$override_res_path || ![info exists g_resolvedPath($modalt)]} {
         set g_resolvedPath($modalt) $target
      }
      lappend g_resolvedHash($res) $modalt
      # register name alternative to know their existence
      set ::g_moduleAltName($modalt) $mod
      set ::g_moduleAltName($mod) $modalt
   }

   # if other modules were pointing to this one, adapt resolution end-point
   set relmod_list {}
   if {[info exists g_resolvedHash($mod)]} {
      set relmod_list $g_resolvedHash($mod)
      unset g_resolvedHash($mod)
   }
   # also adapt resolution for modules pointing to the alternative name
   if {[info exists modalt] && [info exists g_resolvedHash($modalt)]} {
      set relmod_list [concat $relmod_list $g_resolvedHash($modalt)]
      unset g_resolvedHash($modalt)
   }
   foreach relmod $relmod_list {
      set g_moduleResolved($relmod) $res
      reportDebug "setModuleResolution: $relmod now resolved to $res"
      lappend g_resolvedHash($res) $relmod
   }

   # register and propagate symbols to the resolution path
   if {[info exists g_symbolHash($mod)]} {
      set sym_list $g_symbolHash($mod)
   } else {
      set sym_list {}
   }
   if {$symver ne ""} {
      # merge symbol definitions in case of alternative name
      if {[info exists modalt] && [info exists g_symbolHash($modalt)]} {
         set sym_list [lsort -dictionary -unique [concat $sym_list\
            $g_symbolHash($modalt)]]
         reportDebug "setModuleResolution: set symbols '$sym_list' to $mod\
            and $modalt"
         set g_symbolHash($mod) $sym_list
         set g_symbolHash($modalt) $sym_list
      }

      # dictionary-sort symbols and remove eventual duplicates
      set sym_list [lsort -dictionary -unique [concat $sym_list\
         [list $symver]]]

      # propagate symbols in g_symbolHash and g_moduleVersion toward the
      # resolution path, handle that locally if we still work on same
      # modulename, call for a proper resolution as soon as we change of
      # module to get this new resolution registered
      foreach modres $res_path {
         lassign [getModuleNameVersion $modres] modfull modresname
         if {$modname eq $modresname} {
            if {[info exists g_symbolHash($modres)]} {
               set modres_sym_list [lsort -dictionary -unique [concat\
                  $g_symbolHash($modres) $sym_list]]
            } else {
               set modres_sym_list $sym_list
            }
            # sync symbols of alternative name if any
            if {[info exists ::g_moduleAltName($modres)]} {
               set altmodres $::g_moduleAltName($modres)
               reportDebug "setModuleResolution: set symbols\
                  '$modres_sym_list' to $modres and $altmodres"
               set g_symbolHash($altmodres) $modres_sym_list
            } else {
               reportDebug "setModuleResolution: set symbols\
                  '$modres_sym_list' to $modres"
            }
            set g_symbolHash($modres) $modres_sym_list

            # register symbolic version for querying in g_moduleVersion
            foreach symelt $sym_list {
               set modvers "$modresname/$symelt"
               reportDebug "setModuleResolution: module-version $modvers =\
                  $modres"
               set ::g_moduleVersion($modvers) $modres
               set ::g_sourceVersion($modvers) $::ModulesCurrentModulefile
            }
         # as we change of module name a proper resolution call should be
         # made (see below) and will handle the rest of the resolution path
         } else {
            set need_set_res 1
            break
         }
      }
   # when registering an alias, existing symbols on alias source name should
   # be broadcast along the resolution path with a proper resolution call
   # (see below)
   } else {
      lassign [getModuleNameVersion $target] modres modresname
      set need_set_res 1
   }

   # resolution needed to broadcast symbols along resolution path without
   # altering initial path already set for these symbols
   if {[info exists need_set_res]} {
      foreach symelt $sym_list {
         set modvers "$modresname/$symelt"
         reportDebug "setModuleResolution: set resolution for $modvers"
         setModuleResolution $modvers $modres $symelt 0
      }
   }

   return 1
}

# Specifies a default or alias version for a module that points to an 
# existing module version Note that aliases defaults are stored by the
# short module name (not the full path) so aliases and defaults from one
# directory will apply to modules of the same name found in other
# directories.
proc module-version {args} {
   reportDebug "module-version: executing module-version $args"
   lassign [getModuleNameVersion [lindex $args 0] 1] mod modname modversion

   # go for registration only if valid modulename
   if {$mod ne ""} {
      foreach version [lrange $args 1 end] {
         set aliasversion "$modname/$version"
         # do not alter a previously defined alias version
         if {![info exists ::g_moduleVersion($aliasversion)]} {
            setModuleResolution $aliasversion $mod $version
         } else {
            reportWarning "Symbolic version '$aliasversion' already defined"
         }
      }
   }

   if {[currentMode] eq "display" && !$::g_inhibit_dispreport} {
      report "module-version\t$args"
   }
   return {}
}

proc module-alias {args} {
   lassign [getModuleNameVersion [lindex $args 0]] alias
   lassign [getModuleNameVersion [lindex $args 1] 1] mod

   reportDebug "module-alias: $alias = $mod"

   if {[setModuleResolution $alias $mod]} {
      set ::g_moduleAlias($alias) $mod
      set ::g_sourceAlias($alias) $::ModulesCurrentModulefile
   }

   if {[currentMode] eq "display" && !$::g_inhibit_dispreport} {
      report "module-alias\t$args"
   }

   return {}
}

proc module-virtual {args} {
   lassign [getModuleNameVersion [lindex $args 0]] mod
   set modfile [getAbsolutePath [lindex $args 1]]

   reportDebug "module-virtual: $mod = $modfile"

   set ::g_moduleVirtual($mod) $modfile
   set ::g_sourceVirtual($mod) $::ModulesCurrentModulefile

   if {[currentMode] eq "display" && !$::g_inhibit_dispreport} {
      report "module-virtual\t$args"
   }

   return {}
}

proc module {command args} {
   set mode [currentMode]

   # resolve command if alias or shortcut name used
   switch -regexp -- $command {
      {^(add|lo)}           {set command "load"}
      {^(rm|unlo)}          {set command "unload"}
      {^(ref|rel)}          {set command "reload"}
      {^sw}                 {set command "switch"}
      {^(di|show)}          {set command "display"}
      {^av}                 {set command "avail"}
      {^al}                 {set command "aliases"}
      {^li}                 {set command "list"}
      {^wh}                 {set command "whatis"}
      {^(apropos|keyword)$} {set command "search"}
      {^pu}                 {set command "purge"}
      {^init(a|lo)}         {set command "initadd"}
      {^initp}              {set command "initprepend"}
      {^initsw}             {set command "initswitch"}
      {^init(rm|unlo)$}     {set command "initrm"}
      {^initl}              {set command "initlist"}
      {^$}                  {set command "help"; set args {}}
   }

   # guess if called from top level
   set topcall [expr {[info level] == 1}]
   if {$topcall} {
      set msgprefix ""
   } else {
      set msgprefix "module: "

      # some commands can only be called from top level, not within modulefile
      switch -- $command {
         {path} - {paths} - {autoinit} - {help} - {prepend-path} - \
         {append-path} - {remove-path} - {is-loaded} - {is-saved} - \
         {is-used} - {is-avail} - {info-loaded} {
            set errormsg "${msgprefix}Command '$command' not supported"
         }
      }
   }

   # argument number check
   switch -- $command {
      {unload} - {source} - {display} - {initadd} - {initprepend} - \
      {initrm} - {test} - {is-avail} {
         if {[llength $args] == 0} {
            set argnberr 1
         }
      }
      {reload} - {aliases} - {list} - {purge} - {savelist} - {initlist} - \
      {initclear} - {autoinit} {
         if {[llength $args] != 0} {
            set argnberr 1
         }
      }
      {switch} {
         if {[llength $args] == 0 || [llength $args] > 2} {
            set argnberr 1
         }
      }
      {path} - {paths} - {info-loaded} {
         if {[llength $args] != 1} {
            set argnberr 1
         }
      }
      {search} - {save} - {restore} - {saverm} - {saveshow} {
         if {[llength $args] > 1} {
            set argnberr 1
         }
      }
      {initswitch} {
         if {[llength $args] != 2} {
            set argnberr 1
         }
      }
      {prepend-path} - {append-path} - {remove-path} {
         if {[llength $args] < 2} {
            set argnberr 1
         }
      }
   }
   if {[info exists argnberr]} {
      set errormsg "Unexpected number of args for '$command' command"
   }

   # skip command processing if error already spotted
   if {![info exists errormsg]} {
      pushCommandName $command
      switch -- $command {
         {load} {
            # no error raised on empty argument list to cope with
            # initadd command that may expect this behavior
            if {[llength $args] > 0} {
               set ret 0
               if {$topcall || $mode eq "load"} {
                  set ret [eval cmdModuleLoad $args]
               }\
               elseif {$mode eq "unload"} {
                  # on unload mode, unload mods in reverse order
                  set ret [eval cmdModuleUnload "match" [lreverse $args]]
               }\
               elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
                  report "module load\t$args"
               }
               # sub-module interpretation failed, raise error
               if {$ret && !$topcall} {
                  set errormsg "SUB_FAILED"
               }
            }
         }
         {unload} {
            set ret 0
            if {$topcall || $mode eq "load"} {
               set ret [eval cmdModuleUnload "match" $args]
            }\
            elseif {$mode eq "unload"} {
               set ret [eval cmdModuleUnload "match" $args]
            }\
            elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
               report "module unload\t$args"
            }
            # sub-module interpretation failed, raise error
            if {$ret && !$topcall} {
               set errormsg "SUB_FAILED"
            }
         }
         {reload} {
            cmdModuleReload
         }
         {use} {
            if {$topcall || $mode eq "load"} {
               eval cmdModuleUse $args
            } elseif {$mode eq "unload"} {
               eval cmdModuleUnuse $args
            } elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
               report "module use\t$args"
            }
         }
         {unuse} {
            if {$topcall || $mode eq "load" || $mode eq "unload"} {
               eval cmdModuleUnuse $args
            } elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
               report "module unuse\t$args"
            }
         }
         {source} {
            if {$topcall || $mode eq "load"} {
               eval cmdModuleSource $args
            } elseif {$mode eq "unload"} {
               # on unload mode, unsource script in reverse order
               eval cmdModuleUnsource [lreverse $args]
            } elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
               report "module source\t$args"
            }
         }
         {switch} {
            eval cmdModuleSwitch $args
         }
         {display} {
            eval cmdModuleDisplay $args
         }
         {avail} {
            if {$args ne ""} {
               foreach arg $args {
                  cmdModuleAvail $arg
               }
            } else {
               cmdModuleAvail
            }
         }
         {aliases} {
            cmdModuleAliases
         }
         {path} {
            eval cmdModulePath $args
         }
         {paths} {
            eval cmdModulePaths $args
         }
         {list} {
            cmdModuleList
         }
         {whatis} {
            if {$args ne ""} {
               foreach arg $args {
                  cmdModuleWhatIs $arg
               }
            } else {
               cmdModuleWhatIs
            }
         }
         {search} {
            eval cmdModuleApropos $args
         }
         {purge} {
            eval cmdModulePurge
         }
         {save} {
            eval cmdModuleSave $args
         }
         {restore} {
            eval cmdModuleRestore $args
         }
         {saverm} {
            eval cmdModuleSaverm $args
         }
         {saveshow} {
            eval cmdModuleSaveshow $args
         }
         {savelist} {
            cmdModuleSavelist
         }
         {initadd} {
            eval cmdModuleInit add $args
         }
         {initprepend} {
            eval cmdModuleInit prepend $args
         }
         {initswitch} {
            eval cmdModuleInit switch $args
         }
         {initrm} {
            eval cmdModuleInit rm $args
         }
         {initlist} {
            eval cmdModuleInit list $args
         }
         {initclear} {
            eval cmdModuleInit clear $args
         }
         {autoinit} {
            cmdModuleAutoinit
         }
         {help} {
            eval cmdModuleHelp $args
         }
         {test} {
            eval cmdModuleTest $args
         }
         {prepend-path} - {append-path} - {remove-path} {
            eval cmdModuleResurface $command $args
         }
         {is-loaded} - {is-saved} - {is-used} {
            eval cmdModuleResurface $command $args
         }
         {is-avail} {
            eval cmdModuleResurface $command $args
         }
         {info-loaded} {
            eval cmdModuleResurface module-info loaded $args
         }
         default {
            set errormsg "${msgprefix}Invalid command '$command'"
         }
      }
      popCommandName
   }

   # if an error need to be raised, proceed differently depending of
   # call level: if called from top level render errors then raise error
   # elsewhere call is made from a modulefile or modulerc and error
   # will be managed from execute-modulefile or execute-modulerc
   if {[info exists errormsg]} {
      if {$topcall} {
         reportErrorAndExit "$errormsg\nTry 'module --help'\
            for more information."
      } else {
         error "$errormsg"
      }
   # if called from top level render settings if any
   } elseif {$topcall} {
      renderSettings
   }

   return {}
}

proc getModshareVarName {var} {
   # specific modshare variable for DYLD-related variables as a suffixed
   # variable will lead to warning messages with this tool
   if {[string range $var 0 4] eq "DYLD_"} {
      return "MODULES_MODSHARE_${var}"
   } else {
      return "${var}_modshare"
   }
}

proc setenv {var val} {
   set mode [currentMode]

   reportDebug "setenv: ($var,$val) mode = $mode"

   # Set the variable for later use during the modulefile evaluation
   # for all mode except unload
   if {$mode ne "unload"} {
      set ::env($var) $val
      # clean any previously defined reference counter array
      set sharevar [getModshareVarName $var]
      if {[info exists ::env($sharevar)]} {
         unset-env $sharevar
         set sharevarunset 1
      }
   }

   # propagate variable setup to shell environment on load mode
   if {$mode eq "load"} {
      set ::g_stateEnvVars($var) "new"
      if {[info exists sharevarunset]} {
         set ::g_stateEnvVars($sharevar) "del"
      }
   }\
   elseif {$mode eq "unload"} {
      # Don't unset-env here ... it breaks modulefiles
      # that use env(var) is later in the modulefile
      #unset-env $var
      set ::g_stateEnvVars($var) "del"
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "setenv\t\t$var\t$val"
   }
   return {}
}

proc getenv {var} {
   set mode [currentMode]

   reportDebug "getenv: ($var) mode = $mode"

   if {$mode eq "load" || $mode eq "unload"} {
      if {[info exists ::env($var)]} {
         return $::env($var)
      } else {
         return "_UNDEFINED_"
      }
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      return "\$$var"
   }
   return {}
}

proc unsetenv {var {val {}}} {
   set mode [currentMode]

   reportDebug "unsetenv: ($var,$val) mode = $mode"

   if {$mode eq "load"} {
      if {[info exists ::env($var)]} {
         unset-env $var
      }
      set ::g_stateEnvVars($var) "del"
      # clean any existing reference counter array
      set sharevar [getModshareVarName $var]
      if {[info exists ::env($sharevar)]} {
         unset-env $sharevar
         set ::g_stateEnvVars($sharevar) "del"
      }
   }\
   elseif {$mode eq "unload"} {
      if {$val ne ""} {
         set ::env($var) $val
         set ::g_stateEnvVars($var) "new"
      } else {
         set ::g_stateEnvVars($var) "del"
      }
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      if {$val ne ""} {
         report "unsetenv\t$var\t$val"
      } else {
         report "unsetenv\t$var"
      }
   }
   return {}
}

proc chdir {dir} {
   set mode [currentMode]
   set currentModule [currentModuleName]

   reportDebug "chdir: ($dir) mode = $mode"

   if {$mode eq "load"} {
      if {[file exists $dir] && [file isdirectory $dir]} {
         set ::g_changeDir $dir
      } else {
         # report issue but does not treat it as an error to have the
         # same behavior as C-version
         reportWarning "Cannot chdir to '$dir' for '$currentModule'"
      }
   } elseif {$mode eq "unload"} {
      # No operation here unable to undo a syscall.
   } elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "chdir\t\t$dir"
   }

   return {}
}

# superseed exit command to handle it if called within a modulefile
# rather than exiting the whole process
proc exitModfileCmd {{code 0}} {
   set mode [currentMode]

   reportDebug "exit: ($code)"

   if {$mode eq "load"} {
      reportDebug "exit: Inhibit next modulefile interpretations"
      set ::g_inhibit_interp 1
   }

   # break to gently end interpretation of current modulefile
   return -code break
}

# enables slave interp to return ModulesVersion value to the master interp
proc setModulesVersion {val} {
   set ::ModulesVersion $val
}

# supersede puts command to catch content sent to stdout/stderr within
# modulefile in order to correctly send stderr content (if a pager has been
# enabled) or postpone content channel send after rendering on stdout the
# relative environment changes required by the modulefile
proc putsModfileCmd {itrp args} {
   reportDebug "puts: $args (itrp=$itrp)"

   # determine if puts call targets the stdout or stderr channel
   switch -- [llength $args] {
      {1} {
         set deferPuts 1
      }
      {2} {
         switch -- [lindex $args 0] {
            {-nonewline} - {stdout} {
               set deferPuts 1
            }
            {stderr} {
               set reportArgs [list [lindex $args 1]]
            }
         }
      }
      {3} {
         if {[lindex $args 0] eq "-nonewline"} {
            switch -- [lindex $args 1] {
               {stdout} {
                  set deferPuts 1
               }
               {stderr} {
                  set reportArgs [list [lindex $args 2] 1]
               }
            }
         } else {
            set wrongNumArgs 1
         }
      }
      default {
         set wrongNumArgs 1
      }
   }

   # raise error if bad argument number detected, do this here rather in _puts
   # not to confuse people with an error reported by an internal name (_puts)
   if {[info exists wrongNumArgs]} {
      error "wrong # args: should be \"puts ?-nonewline? ?channelId? string\""
   # defer puts if it targets stdout (see renderSettings)
   } elseif {[info exists deferPuts]} {
      lappend ::g_stdoutPuts $args
   # if it targets stderr call report, which knows what channel to use
   } elseif {[info exists reportArgs]} {
      eval report $reportArgs
   # pass to real puts command if not related to stdout and do that in modfile
   # interpreter context to get access to eventual specific channel
   } else {
      $itrp eval _puts $args
   }
}

########################################################################
# path fiddling
#
proc getReferenceCountArray {var separator} {
   set sharevar [getModshareVarName $var]
   set modshareok 1
   if {[info exists ::env($sharevar)]} {
      if {[info exists ::env($var)]} {
         set modsharelist [psplit $::env($sharevar) [getPathSeparator]]
         set temp [expr {[llength $modsharelist] % 2}]

         if {$temp == 0} {
            array set countarr $modsharelist

            # sanity check the modshare list
            array set fixers {}
            array set usagearr {}

            # do not skip a bare empty path entry that can also be found in
            # reference counter array (sometimes var is cleared by setting it
            # empty not unsetting it, ignore var in this case)
            if {$::env($var) eq "" && [info exists countarr()]} {
               set usagearr() 1
            } else {
               foreach dir [split $::env($var) $separator] {
                  set usagearr($dir) 1
               }
            }
            foreach path [array names countarr] {
               if {! [info exists usagearr($path)]} {
                  unset countarr($path)
                  set fixers($path) 1
               }
            }

            foreach path [array names usagearr] {
               if {! [info exists countarr($path)]} {
                  # if no ref count found for a path, assume it has a ref
                  # count of 1 to be able to unload it easily if needed
                  set countarr($path) 1
               }
            }

            if {!$::g_force && [array size fixers]} {
               reportWarning "\$$var does not agree with \$$sharevar counter.\
                  The following directories' usage counters were adjusted to\
                  match. Note that this may mean that module unloading may\
                  not work correctly."
               foreach dir [array names fixers] {
                  report " $dir" -nonewline
               }
               report ""
            }
         } else {
            # sharevar was corrupted, odd number of elements.
            set modshareok 0
         }
      # nullify modshare if a SIP-protected var is not found in context as
      # this kind of variable is not exported to subshell on OSX when SIP
      # is enabled
      } elseif {([string range $var 0 4] eq "DYLD_" || [string range\
         $var 0 2] eq "LD_") && $::tcl_platform(os) eq "Darwin"} {
         set modshareok 0
      } else {
         reportWarning "$sharevar exists ( $::env($sharevar) ), but $var\
            doesn't. Environment is corrupted."
         set modshareok 0
      }
   } else {
      set modshareok 0
   }

   if {$modshareok == 0 && [info exists ::env($var)]} {
      array set countarr {}
      foreach dir [split $::env($var) $separator] {
         set countarr($dir) 1
      }
   }

   set count_list [array get countarr]
   reportDebug "getReferenceCountArray: (var=$var, delim=$separator) got\
      '$count_list'"

   return $count_list
}


proc unload-path {args} {
   reportDebug "unload-path: ($args)"

   lassign [eval parsePathCommandArgs "unload-path" $args] separator\
      allow_dup idx_val var path_list

   array set countarr [getReferenceCountArray $var $separator]

   # Don't worry about dealing with this variable if it is already scheduled
   #  for deletion
   if {[info exists ::g_stateEnvVars($var)] && $::g_stateEnvVars($var) eq\
      "del"} {
      return {}
   }

   # save initial variable content to match index arguments
   if {[info exists ::env($var)]} {
      set dir_list [split $::env($var) $separator]
      # detect if empty env value means empty path entry
      if {[llength $dir_list] == 0 && [info exists countarr()]} {
         lappend dir_list {}
      }
   } else {
      set dir_list [list]
   }

   # build list of index to remove from variable
   set del_idx_list [list]
   foreach dir $path_list {
      # retrieve dir value if working on an index list
      if {$idx_val} {
         set idx $dir
         # go to next index if this one is not part of the existing range
         # needed to distinguish an empty value to an out-of-bound value
         if {$idx < 0 || $idx >= [llength $dir_list]} {
            continue
         } else {
            set dir [lindex $dir_list $idx]
         }
      }

      # update reference counter array
      if {[info exists countarr($dir)]} {
         incr countarr($dir) -1
         set newcount $countarr($dir)
         if {$countarr($dir) <= 0} {
            unset countarr($dir)
         }
      } else {
         set newcount 0
      }

      # get all entry indexes corresponding to dir
      set found_idx_list [lsearch -all -exact $dir_list $dir]

      # remove all found entries
      if {$::g_force || $newcount <= 0} {
         # only remove passed position in --index mode
         if {$idx_val} {
            lappend del_idx_list $idx
         } else {
            set del_idx_list [concat $del_idx_list $found_idx_list]
         }
      # if multiple entries found remove the extra entries compared to new
      # reference counter
      } elseif {[llength $found_idx_list] > $newcount} {
         # only remove passed position in --index mode
         if {$idx_val} {
            lappend del_idx_list $idx
         } else {
            # delete extra entries, starting from end of the list (on a path
            # variable, entries at the end have less priority than those at
            # the start)
            set del_idx_list [concat $del_idx_list [lrange $found_idx_list\
               $newcount end]]
         }
      }
   }

   # update variable if some element need to be removed
   if {[llength $del_idx_list] > 0} {
      set del_idx_list [lsort -integer -unique $del_idx_list]
      set newpath [list]
      set nbelem [llength $dir_list]
      # rebuild list of element without indexes set for deletion
      for {set i 0} {$i < $nbelem} {incr i} {
         if {[lsearch -exact $del_idx_list $i] == -1} {
            lappend newpath [lindex $dir_list $i]
         }
      }
   } else {
      set newpath $dir_list
   }

   # set env variable and corresponding reference counter in any case
   if {[llength $newpath] == 0} {
      unset-env $var
      set ::g_stateEnvVars($var) "del"
   } else {
      set ::env($var) [join $newpath $separator]
      set ::g_stateEnvVars($var) "new"
   }

   set sharevar [getModshareVarName $var]
   if {[array size countarr] > 0} {
      set ::env($sharevar) [pjoin [array get countarr] [getPathSeparator]]
      set ::g_stateEnvVars($sharevar) "new"
   } else {
      unset-env $sharevar
      set ::g_stateEnvVars($sharevar) "del"
   }
   return {}
}

proc add-path {pos args} {
   reportDebug "add-path: ($args) pos=$pos"

   lassign [eval parsePathCommandArgs "add-path" $args] separator allow_dup\
      idx_val var path_list

   set sharevar [getModshareVarName $var]
   array set countarr [getReferenceCountArray $var $separator]

   if {$pos eq "prepend"} {
      set path_list [lreverse $path_list]
   }

   foreach dir $path_list {
      if {![info exists countarr($dir)] || $allow_dup} {
         # ignore env var set empty if no empty entry found in reference
         # counter array (sometimes var is cleared by setting it empty not
         # unsetting it)
         if {[info exists ::env($var)] && ($::env($var) ne "" ||\
            [info exists countarr()])} {
            if {$pos eq "prepend"} {
               set ::env($var) "$dir$separator$::env($var)"
            } else {
               set ::env($var) "$::env($var)$separator$dir"
            }
         } else {
            set ::env($var) "$dir"
         }
      }
      if {[info exists countarr($dir)]} {
         incr countarr($dir)
      } else {
         set countarr($dir) 1
      }
      reportDebug "add-path: env($var) = $::env($var)"
   }

   set ::env($sharevar) [pjoin [array get countarr] [getPathSeparator]]
   set ::g_stateEnvVars($var) "new"
   set ::g_stateEnvVars($sharevar) "new"
   return {}
}

# analyze argument list passed to a path command to set default value or raise
# error in case some attributes are missing
proc parsePathCommandArgs {cmd args} {
   # parse argument list
   set next_is_delim 0
   set allow_dup 0
   set idx_val 0
   foreach arg $args {
      switch -glob -- $arg {
         {--index} {
            if {$cmd eq "add-path"} {
               reportWarning "--index option has no effect on $cmd"
            } else {
               set idx_val 1
            }
         }
         {--duplicates} {
            if {$cmd eq "unload-path"} {
               reportWarning "--duplicates option has no effect on $cmd"
            } else {
               set allow_dup 1
            }
         }
         {-d} - {-delim} - {--delim} {
            set next_is_delim 1
         }
         {--delim=*} {
            set delim [string range $arg 8 end]
         }
         default {
            if {$next_is_delim} {
               set delim $arg
               set next_is_delim 0
            } elseif {![info exists var]} {
               set var $arg
            } else {
               # set multiple passed values in a list
               lappend val_raw_list $arg
            }
         }
      }
   }

   # adapt with default value or raise error if some arguments are missing
   if {![info exists delim]} {
      set delim [getPathSeparator]
   } elseif {$delim eq ""} {
      error "$cmd should get a non-empty path delimiter"
   }
   if {![info exists var]} {
      error "$cmd should get an environment variable name"
   } elseif {$var eq ""} {
      error "$cmd should get a valid environment variable name"
   }
   if {![info exists val_raw_list]} {
      error "$cmd should get a value for environment variable $var"
   }

   # set list of value to add
   set val_list [list]
   foreach val $val_raw_list {
      # check passed indexes are numbers
      if {$idx_val && ![string is integer -strict $val]} {
         error "$cmd should get valid number as index value"
      }

      switch -- $val \
         {} {
            # add empty entry in list
            lappend val_list {}
         } \
         $delim {
            error "$cmd cannot handle path equals to separator string"
         } \
         default {
            # split passed value with delimiter
            set val_list [concat $val_list [split $val $delim]]
         }
   }

   reportDebug "parsePathCommandArgs: (delim=$delim, allow_dup=$allow_dup,\
      idx_val=$idx_val, var=$var, val=$val_list, nbval=[llength $val_list])"

   return [list $delim $allow_dup $idx_val $var $val_list]
}

proc prepend-path {args} {
   set mode [currentMode]

   reportDebug "prepend-path: ($args) mode=$mode"

   if {$mode eq "load"} {
      eval add-path "prepend" $args
   }\
   elseif {$mode eq "unload"} {
      eval unload-path $args
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "prepend-path\t$args"
   }

   return {}
}

proc append-path {args} {
   set mode [currentMode]

   reportDebug "append-path: ($args) mode=$mode"

   if {$mode eq "load"} {
      eval add-path "append" $args
   }\
   elseif {$mode eq "unload"} {
      eval unload-path $args
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "append-path\t$args"
   }

   return {}
}

proc remove-path {args} {
   set mode [currentMode]

   reportDebug "remove-path: ($args) mode=$mode"

   if {$mode eq "load"} {
      eval unload-path $args
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "remove-path\t$args"
   }
   return {}
}

proc set-alias {alias what} {
   set mode [currentMode]

   reportDebug "set-alias: ($alias, $what) mode=$mode"
   if {$mode eq "load"} {
      set ::g_Aliases($alias) $what
      set ::g_stateAliases($alias) "new"
   }\
   elseif {$mode eq "unload"} {
      set ::g_Aliases($alias) {}
      set ::g_stateAliases($alias) "del"
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "set-alias\t$alias\t$what"
   }

   return {}
}

proc unset-alias {alias} {
   set mode [currentMode]

   reportDebug "unset-alias: ($alias) mode=$mode"
   if {$mode eq "load"} {
      set ::g_Aliases($alias) {}
      set ::g_stateAliases($alias) "del"
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "unset-alias\t$alias"
   }

   return {}
}

proc is-loaded {args} {
   reportDebug "is-loaded: $args"

   foreach mod $args {
      if {[getLoadedMatchingName $mod "returnfirst"] ne ""} {
         return 1
      }
   }
   # is something loaded whatever it is?
   return [expr {[llength $args] == 0 && [llength [getLoadedModuleList]] > 0}]
}

proc conflict {args} {
   set mode [currentMode]
   set currentModule [currentModuleName]

   reportDebug "conflict: ($args) mode = $mode"

   if {$mode eq "load"} {
      foreach mod $args {
         # If the current module is already loaded, we can proceed
         if {![is-loaded $currentModule]} {
            # otherwise if the conflict module is loaded, we cannot
            if {[is-loaded $mod]} {
               set errMsg "WARNING: $currentModule cannot be loaded due\
                  to a conflict."
               set errMsg "$errMsg\nHINT: Might try \"module unload\
                  $mod\" first."
               error $errMsg
            }
         }
      }
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "conflict\t$args"
   }

   return {}
}

proc prereq {args} {
   set mode [currentMode]
   set currentModule [currentModuleName]

   reportDebug "prereq: ($args) mode = $mode"

   if {$mode eq "load"} {
      if {![eval is-loaded $args]} {
         set errMsg "WARNING: $currentModule cannot be loaded due to\
             missing prereq."
         # adapt error message when multiple modules are specified
         if {[llength $args] > 1} {
            set errMsg "$errMsg\nHINT: at least one of the following\
               modules must be loaded first: $args"
         } else {
            set errMsg "$errMsg\nHINT: the following module must be\
               loaded first: $args"
         }
         error $errMsg
      }
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "prereq\t\t$args"
   }

   return {}
}

proc x-resource {resource {value {}}} {
   set mode [currentMode]

   reportDebug "x-resource: ($resource, $value)"

   # sometimes x-resource value may be provided within resource name
   # as the "x-resource {Ileaf.popup.saveUnder: True}" example provided
   # in manpage. so here is an attempt to extract real resource name and
   # value from resource argument
   if {[string length $value] == 0 && ![file exists $resource]} {
      # look first for a space character as delimiter, then for a colon
      set sepapos [string first " " $resource]
      if { $sepapos == -1 } {
         set sepapos [string first ":" $resource]
      }

      if { $sepapos > -1 } {
         set value [string range $resource [expr {$sepapos + 1}] end]
         set resource [string range $resource 0 [expr {$sepapos - 1}]]
         reportDebug "x-resource: corrected ($resource, $value)"
      } else {
         # if not a file and no value provided x-resource cannot be
         # recorded as it will produce an error when passed to xrdb
         reportWarning "x-resource $resource is not a valid string or file"
         return {}
      }
   }

   # check current environment can handle X11 resource edition elsewhere exit
   if {($mode eq "load" || $mode eq "unload") &&\
      [catch {runCommand xrdb -query} errMsg]} {
      error "WARNING: X11 resources cannot be edited, issue spotted\n$errMsg"
   }

   # if a resource does hold an empty value in g_newXResources or
   # g_delXResources arrays, it means this is a resource file to parse
   if {$mode eq "load"} {
      set ::g_newXResources($resource) $value
   }\
   elseif {$mode eq "unload"} {
      set ::g_delXResources($resource) $value
   }\
   elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      report "x-resource\t$resource\t$value"
   }

   return {}
}

proc uname {what} {
   set result {}

   reportDebug "uname: called: $what"

   if {! [info exists ::unameCache($what)]} {
      switch -- $what {
         {sysname} {
            set result $::tcl_platform(os)
         }
         {machine} {
            set result $::tcl_platform(machine)
         }
         {nodename} - {node} {
            set result [runCommand uname -n]
         }
         {release} {
            set result $::tcl_platform(osVersion)
         }
         {domain} {
            set result [runCommand domainname]
         }
         {version} {
            set result [runCommand uname -v]
         }
         default {
            error "uname $what not supported"
         }
      }
      set ::unameCache($what) $result
   }

   return $::unameCache($what)
}

proc system {mycmd args} {
   reportDebug "system: $mycmd $args"

   set mode [currentMode]
   set status {}

   if {$mode eq "load" || $mode eq "unload"} {
      if {[catch {exec >&@stderr $mycmd $args}]} {
          # non-zero exit status, get it:
          set status [lindex $::errorCode 2]
      } else {
          # exit status was 0
          set status 0
      }
   } elseif {$mode eq "display" && !$::g_inhibit_dispreport} {
      if {[llength $args] == 0} {
         report "system\t\t$mycmd"
      } else {
         report "system\t\t$mycmd $args"
      }
   }

   return $status
}

# test at least one of the collections passed as argument exists
proc is-saved {args} {
   reportDebug "is-saved: $args"

   foreach coll $args {
      lassign [getCollectionFilename $coll] collfile colldesc
      if {[file exists $collfile]} {
         return 1
      }
   }
   # is something saved whatever it is?
   return [expr {[llength $args] == 0 && [llength [findCollections]] > 0}]
}

# test at least one of the directories passed as argument is set in MODULEPATH
proc is-used {args} {
   reportDebug "is-used: $args"

   set modpathlist [getModulePathList]
   foreach path $args {
      # transform given path in an absolute path to compare with dirs
      # registered in the MODULEPATH env var which are returned absolute.
      set abspath [getAbsolutePath $path]
      if {[lsearch -exact $modpathlist $abspath] >= 0} {
         return 1
      }
   }
   # is something used whatever it is?
   return [expr {[llength $args] == 0 && [llength $modpathlist] > 0}]
}

# test at least one of the modulefiles passed as argument exists
proc is-avail {args} {
   reportDebug "is-avail: $args"
   set ret 0

   # disable error reporting to avoid modulefile errors
   # to pollute result. Only if not already inhibited
   set alreadyinhibit [isErrorReportInhibited]
   if {!$alreadyinhibit} {
      inhibitErrorReport
   }

   foreach mod $args {
      lassign [getPathToModule $mod] modfile modname
      if {$modfile ne ""} {
         set ret 1
         break
      }
   }

   # re-enable only is it was disabled from this procedure
   if {!$alreadyinhibit} {
      reenableErrorReport
   }
   return $ret
}

########################################################################
# internal module procedures
#
set g_modeStack {}

proc currentMode {} {
   return [lindex $::g_modeStack end]
}

proc pushMode {mode} {
   lappend ::g_modeStack $mode
}

proc popMode {} {
   set ::g_modeStack [lrange $::g_modeStack 0 end-1]
}

set g_moduleNameStack {}

proc currentModuleName {} {
   return [lindex $::g_moduleNameStack end]
}

proc pushModuleName {moduleName} {
   lappend ::g_moduleNameStack $moduleName
}

proc popModuleName {} {
   set ::g_moduleNameStack [lrange $::g_moduleNameStack 0 end-1]
}

set g_moduleFileStack {}

proc pushModuleFile {modfile} {
   lappend ::g_moduleFileStack $modfile
   set ::ModulesCurrentModulefile $modfile
}

proc popModuleFile {} {
   set ::g_moduleFileStack [lrange $::g_moduleFileStack 0 end-1]
   set ::ModulesCurrentModulefile [lindex $::g_moduleFileStack end]
}

set g_specifiedNameStack {}

proc currentSpecifiedName {} {
   return [lindex $::g_specifiedNameStack end]
}

proc pushSpecifiedName {specifiedName} {
   lappend ::g_specifiedNameStack $specifiedName
}

proc popSpecifiedName {} {
   set ::g_specifiedNameStack [lrange $::g_specifiedNameStack 0 end-1]
}

set g_commandNameStack {}

proc currentCommandName {} {
   return [lindex $::g_commandNameStack end]
}

proc pushCommandName {commandName} {
   lappend ::g_commandNameStack $commandName
}

proc popCommandName {} {
   set ::g_commandNameStack [lrange $::g_commandNameStack 0 end-1]
}


# return list of loaded modules by parsing LOADEDMODULES env variable
proc getLoadedModuleList {{filter_empty 1}} {
   if {[info exists ::env(LOADEDMODULES)]} {
      set modlist [list]
      foreach mod [split $::env(LOADEDMODULES) [getPathSeparator]] {
         # ignore empty element
         if {$mod ne "" || !$filter_empty} {
            lappend modlist $mod
         }
      }
      return $modlist
   } else {
      return {}
   }
}

# return list of loaded module files by parsing _LMFILES_ env variable
proc getLoadedModuleFileList {} {
   if {[info exists ::env(_LMFILES_)]} {
      set modfilelist [list]
      foreach modfile [split $::env(_LMFILES_) [getPathSeparator]] {
         # ignore empty element
         if {$modfile ne ""} {
            lappend modfilelist $modfile
         }
      }
      return $modfilelist
   } else {
      return {}
   }
}

# return list of module paths by parsing MODULEPATH env variable
# behavior param enables to exit in error when no MODULEPATH env variable
# is set. by default an empty list is returned if no MODULEPATH set
# resolv_var param tells if environement variable references in path elements
# should be resolved or passed as-is in result list
# set_abs param applies an absolute path name convertion to path elements
# if enabled
proc getModulePathList {{behavior "returnempty"} {resolv_var 1} {set_abs 1}} {
   if {[info exists ::env(MODULEPATH)]} {
      set modpathlist [list]
      foreach modpath [split $::env(MODULEPATH) [getPathSeparator]] {
         # ignore empty element
         if {$modpath ne ""} {
            if {$resolv_var} {
               set modpath [resolvStringWithEnv $modpath]
            }
            if {$set_abs} {
               set modpath [getAbsolutePath $modpath]
            }
            lappend modpathlist $modpath
         }
      }
      return $modpathlist
   } elseif {$behavior eq "exiterronundef"} {
      reportErrorAndExit "No module path defined"
   } else {
      return {}
   }
}

# test if two modules share the same root name
proc isSameModuleRoot {mod1 mod2} {
   set mod1split [split $mod1 "/"]
   set mod2split [split $mod2 "/"]

   return [expr {[lindex $mod1split 0] eq [lindex $mod2split 0]}]
}

# test if one element in module name has a leading "dot" making this module
# a hidden module
proc isModuleHidden {mod} {
   foreach elt [split $mod "/"] {
      if {[string index $elt 0] eq "."} {
         return 1
      }
   }
   return 0
}

# check if module name is specified as a full pathname (not a name relative
# to a modulepath)
proc isModuleFullPath {mod} {
   return [regexp {^(|\.|\.\.)/} $mod]
}

# check if a module corresponds to a virtual module (module name
# does not corresponds to end of the modulefile name)
proc isModuleVirtual {mod modfile} {
   return [expr {[string first $mod $modfile end-[string length $mod]] == -1}]
}

# Return the full pathname and modulename to the module.  
# Resolve aliases and default versions if the module name is something like
# "name/version" or just "name" (find default version).
proc getPathToModule {mod {indir {}} {look_loaded "no"} {excdir {}}} {
   reportDebug "getPathToModule: finding '$mod' in '$indir' (excdir='')"

   if {$mod eq ""} {
      set retlist [list "" 0 "none" "Invalid empty module name"]
   # try first to look at loaded modules if enabled to find maching module
   # or to find a closest match (used when switching with single name arg)
   } elseif {($look_loaded eq "match" && [set lm [getLoadedMatchingName\
      $mod]] ne "") || ($look_loaded eq "close" && [set lm\
      [getLoadedWithClosestName $mod]] ne "")} {
      set retlist [list [getModulefileFromLoadedModule $lm] $lm]
   # Check for $mod specified as a full pathname
   } elseif {[isModuleFullPath $mod]} {
      set mod [getAbsolutePath $mod]
      # note that a raw filename as an argument returns the full
      # path as the module name
      lassign [checkValidModule $mod] check_valid check_msg
      switch -- $check_valid {
         {true} {
            set retlist [list $mod $mod]
         }
         {invalid} - {accesserr} {
            set retlist [list "" $mod $check_valid $check_msg $mod]
         }
      }
   } else {
      if {$indir ne ""} {
         set dir_list $indir
      } else {
         set dir_list [getModulePathList "exiterronundef"]
      }
      # remove excluded directories (already searched)
      foreach dir $excdir {
         set dir_list [replaceFromList $dir_list $dir]
      }

      # modparent is the the modulename minus the module version.
      lassign [getModuleNameVersion $mod] mod modparent modversion
      set modroot [lindex [split $mod "/"] 0]
      # determine if we need to get hidden modules
      set fetch_hidden [isModuleHidden $mod]

      # Now search for $mod in module paths
      foreach dir $dir_list {
         # get list of modules related to the root of searched module to get
         # in one call a complete list of any module kind (file, alias, etc)
         # related to search to be able to then determine in this proc the
         # correct module to return without restarting new searches
         array unset mod_list
         array set mod_list [getModules $dir $modroot 0 "rc_defs_included"\
            $fetch_hidden]

         set prevmod ""
         set mod_res ""
         # loop to resolve correct modulefile in case specified mod is a
         # directory that should be analyzed to get default mod in it
         while {$prevmod ne $mod} {
            set prevmod $mod

            if {[info exists mod_list($mod)]} {
               switch -- [lindex $mod_list($mod) 0] {
                  {alias} - {version} {
                     set newmod [resolveModuleVersionOrAlias $mod]
                     # continue search on newmod if module from same root and
                     # not hidden (if hidden search disabled) as mod_list
                     # already contains everything related to this root module
                     if {[isSameModuleRoot $mod $newmod] && ($fetch_hidden ||\
                        ![isModuleHidden $newmod])} {
                        set mod $newmod
                        # indicate an alias or a symbol was solved
                        set mod_res $newmod
                     # elsewhere restart search on new modulename, constrained
                     # to specified dir if set
                     } else {
                        return [getPathToModule $newmod $indir]
                     }
                  }
                  {directory} {
                     # Move to default element in directory
                     set mod "$mod/[lindex $mod_list($mod) 1]"
                     # restart search if default element is hidden and hidden
                     # elements were not searched
                     if {!$fetch_hidden && [isModuleHidden $mod]} {
                        return [getPathToModule $mod $indir]
                     }
                  }
                  {modulefile} {
                     # If mod was a file in this path, return that file
                     set retlist [list "$dir/$mod" $mod]
                  }
                  {virtual} {
                     # return virtual name with file it targets
                     set retlist [list [lindex $mod_list($mod) 2] $mod]
                  }
                  {invalid} - {accesserr} {
                     # may found mod but issue, so end search with error
                     set retlist [concat [list "" $mod] $mod_list($mod)]
                  }
               }
            }
         }
         # break loop if found something (valid or invalid module)
         # elsewhere go to next path
         if {[info exists retlist]} {
            break
         # found nothing after solving a matching alias or symbol
         } elseif {$mod_res eq $mod} {
            lappend excdir $dir
            # look for this name in the other module paths, so restart
            # directory search from first dir in list to ensure precedence
            return [getPathToModule $mod $indir "no" $excdir]
         }
      }
   }

   # set result if nothing found
   if {![info exists retlist]} {
      set retlist [list "" $mod "none" "Unable to locate a modulefile for\
         '$mod'"]
   }
   if {[lindex $retlist 0] ne ""} {
      reportDebug "getPathToModule: found '[lindex $retlist 0]' as\
         '[lindex $retlist 1]'"
   } else {
      eval reportIssue [lrange $retlist 2 4]
   }
   return $retlist
}

proc isModuleLoaded {mod} {
   cacheCurrentModules

   return [info exists ::g_loadedModules($mod)]
}

proc getModulefileFromLoadedModule {mod} {
   if {[isModuleLoaded $mod]} {
      return $::g_loadedModules($mod)
   } else {
      return {}
   }
}

proc isModulefileLoaded {modfile} {
   cacheCurrentModules

   return [info exists ::g_loadedModuleFiles($modfile)]
}

proc getModuleFromLoadedModulefile {modfile {idx "all"}} {
   set ret {}

   if {[isModulefileLoaded $modfile]} {
      if {$idx eq "all"} {
         set ret $::g_loadedModuleFiles($modfile)
      } else {
         set ret [lindex $::g_loadedModuleFiles($modfile) $idx]
      }
   }

   return $ret
}

proc setLoadedModule {mod modfile} {
   set ::g_loadedModules($mod) $modfile
   # a loaded modfile may correspond to multiple loaded virtual modules
   lappend ::g_loadedModuleFiles($modfile) $mod
}

proc unsetLoadedModule {mod modfile} {
   unset ::g_loadedModules($mod)
   # a loaded modfile may correspond to multiple loaded virtual modules
   if {[llength $::g_loadedModuleFiles($modfile)] == 1} {
      unset ::g_loadedModuleFiles($modfile)
   } else {
      set ::g_loadedModuleFiles($modfile) [replaceFromList\
         $::g_loadedModuleFiles($modfile) $mod]
   }
}

# return the currently loaded module whose name is the closest to the
# name passed as argument. if no loaded module match at least one part
# of the passed name, an empty string is returned.
proc getLoadedWithClosestName {name} {
   set ret ""
   set retmax 0

   if {[isModuleFullPath $name]} {
      set fullname [getAbsolutePath $name]
      # if module is passed as full modulefile path name, get corresponding
      # short name from used modulepaths
      if {[set shortname [findModuleNameFromModulefile $fullname]] ne ""} {
         set namesplit [split $shortname "/"]
      # or look at lmfile names to return the eventual exact match
      } else {
         # module may be loaded with its full path name
         if {[isModuleLoaded $fullname]} {
            set ret $fullname
         # or name corresponds to the _lmfiles_ entry of a virtual modules in
         # which case lastly loaded virtual module is returned
         } elseif {[isModulefileLoaded $fullname]} {
            set ret [getModuleFromLoadedModulefile $fullname end]
         }
      }
   } else {
      set namesplit [split $name "/"]
   }

   if {[info exists namesplit]} {
      # compare name to each currently loaded module name
      foreach mod [getLoadedModuleList] {
         # if module loaded as fullpath but test name not, try to get loaded
         # mod short name (with currently used modulepaths) to compare it
         if {[isModuleFullPath $mod] && [set modname\
            [findModuleNameFromModulefile $mod]] ne ""} {
            set modsplit [split $modname "/"]
         } else {
            set modsplit [split $mod "/"]
         }

         # min expr function is not supported in Tcl8.4 and earlier
         if {[llength $namesplit] < [llength $modsplit]} {
            set imax [llength $namesplit]
         } else {
            set imax [llength $modsplit]
         }

         # compare each element of the name to find closest answer
         # in case of equality, last loaded module will be returned as it
         # overwrites previously found value
         for {set i 0} {$i < $imax} {incr i} {
            if {[lindex $modsplit $i] eq [lindex $namesplit $i]} {
               if {$i >= $retmax} {
                  set retmax $i
                  set ret $mod
               }
            } else {
               # end of match, go next mod
               break
            }
         }
      }
   }

   reportDebug "getLoadedWithClosestName: '$ret' closest to '$name'"

   return $ret
}

# return the currently loaded module whose name is equal or include the name
# passed as argument. if no loaded module match, an empty string is returned.
proc getLoadedMatchingName {name {behavior "returnlast"}} {
   set ret {}
   set retmax 0

   # if module is passed as full modulefile path name, look at lmfile names
   # to return the eventual exact match
   if {[isModuleFullPath $name]} {
      set mod [getAbsolutePath $name]
      # if module is loaded with its full path name loadedmodules entry is
      # equivalent to _lmfiles_ corresponding entry so only check _lmfiles_
      if {[isModulefileLoaded $mod]} {
         # a loaded modfile may correspond to multiple loaded virtual modules
         switch -- $behavior {
            {returnlast} {
               # the last loaded module will be returned
               set ret [getModuleFromLoadedModulefile $mod end]
            }
            {returnfirst} {
               # the first loaded module will be returned
               set ret [getModuleFromLoadedModulefile $mod 0]
            }
            {returnall} {
               # all loaded modules will be returned
               set ret [getModuleFromLoadedModulefile $mod]
            }
         }
      }
   } elseif {$name ne ""} {
      # compare name to each currently loaded module name, if multiple mod
      # match name:
      foreach mod [getLoadedModuleList] {
         # if module loaded as fullpath but test name not, try to get loaded
         # mod short name (with currently used modulepaths) to compare it
         if {[isModuleFullPath $mod] && [set modname\
            [findModuleNameFromModulefile $mod]] ne ""} {
            set matchmod "$modname/"
         } else {
            set matchmod $mod
         }
         if {[string first "$name/" "$matchmod/"] == 0} {
            switch -- $behavior {
               {returnlast} {
                  # the last loaded module will be returned
                  set ret $mod
               }
               {returnfirst} {
                  # the first loaded module will be returned
                  set ret $mod
                  break
               }
               {returnall} {
                  # all loaded modules will be returned
                  lappend ret $mod
               }
            }
         }
      }
   }

   reportDebug "getLoadedMatchingName: '$ret' matches '$name'"

   return $ret
}

# runs the global RC files if they exist
proc runModulerc {} {
   set rclist {}

   reportDebug "runModulerc: running..."

   if {[info exists ::env(MODULERCFILE)]} {
      # if MODULERCFILE is a dir, look at a modulerc file in it
      if {[file isdirectory $::env(MODULERCFILE)]\
         && [file isfile "$::env(MODULERCFILE)/modulerc"]} {
         lappend rclist "$::env(MODULERCFILE)/modulerc"
      } elseif {[file isfile $::env(MODULERCFILE)]} {
         lappend rclist $::env(MODULERCFILE)
      }
   }
   if {[file isfile "/usr/share/Modules/etc/rc"]} {
      lappend rclist "/usr/share/Modules/etc/rc"
   }
   if {[info exists ::env(HOME)] && [file isfile "$::env(HOME)/.modulerc"]} {
      lappend rclist "$::env(HOME)/.modulerc"
   }

   foreach rc $rclist {
      if {[file readable $rc]} {
         reportDebug "runModulerc: Executing $rc"
         cmdModuleSource "$rc"
      }
   }

   # identify alias or symbolic version set in these global RC files to be
   # able to include them or not in output or resolution processes
   array set ::g_rcAlias [array get ::g_moduleAlias]
   array set ::g_rcVersion [array get ::g_moduleVersion]
   array set ::g_rcVirtual [array get ::g_moduleVirtual]
}

# manage settings to save as a stack to have a separate set of settings
# for each module loaded or unloaded in order to be able to restore the
# correct set in case of failure
proc pushSettings {} {
   foreach var {env g_Aliases g_stateEnvVars g_stateAliases g_newXResource\
      g_delXResource} {
      eval "lappend ::g_SAVE_$var \[array get ::$var\]"
   }
}

proc popSettings {} {
   foreach var {env g_Aliases g_stateEnvVars g_stateAliases g_newXResource\
      g_delXResource} {
      eval "set ::g_SAVE_$var \[lrange \$::g_SAVE_$var 0 end-1\]"
   }
}

proc restoreSettings {} {
   foreach var {env g_Aliases g_stateEnvVars g_stateAliases g_newXResource\
      g_delXResource} {
      # clear current $var arrays
      if {[info exists ::$var]} {
         eval "unset ::$var; array set ::$var {}"
      }
      eval "array set ::$var \[lindex \$::g_SAVE_$var end\]"
   }
}

proc renderSettings {} {
   global g_stateEnvVars g_stateAliases g_newXResources g_delXResources

   reportDebug "renderSettings: called."

   # required to work on ygwin, shouldn't hurt real linux
   fconfigure stdout -translation lf

   # preliminaries if there is stuff to render
   if {$::g_autoInit || [array size g_stateEnvVars] > 0 ||\
      [array size g_stateAliases] > 0 || [array size g_newXResources] > 0 ||\
      [array size g_delXResources] > 0 || [info exists ::g_changeDir] ||\
      [info exists ::g_stdoutPuts] || [info exists ::g_return_text]} {
      switch -- $::g_shellType {
         {python} {
            puts stdout "import os"
         }
      }
      set has_rendered 1
   } else {
      set has_rendered 0
   }

   if {$::g_autoInit} {
      renderAutoinit
   }

   # new environment variables
   foreach var [array names g_stateEnvVars] {
      switch -- $g_stateEnvVars($var) {
         {new} {
            switch -- $::g_shellType {
               {csh} {
                  set val [charEscaped $::env($var)]
                  # csh barfs on long env vars
                  if {$::g_shell eq "csh" && [string length $val] >\
                     $::CSH_LIMIT} {
                     if {$var eq "PATH"} {
                        reportWarning "PATH exceeds $::CSH_LIMIT characters,\
                           truncating and appending /usr/bin:/bin ..."
                        set val [string range $val 0 [expr {$::CSH_LIMIT\
                           - 1}]]:/usr/bin:/bin
                     } else {
                         reportWarning "$var exceeds $::CSH_LIMIT characters,\
                            truncating..."
                         set val [string range $val 0 [expr {$::CSH_LIMIT\
                            - 1}]]
                     }
                  }
                  puts stdout "setenv $var $val;"
               }
               {sh} {
                  puts stdout "$var=[charEscaped $::env($var)];\
                     export $var;"
               }
               {fish} {
                  set val [charEscaped $::env($var)]
                  # fish shell has special treatment for PATH variable
                  # so its value should be provided as a list separated
                  # by spaces not by semi-colons
                  if {$var eq "PATH"} {
                     regsub -all ":" $val " " val
                  }
                  puts stdout "set -xg $var $val;"
               }
               {tcl} {
                  set val $::env($var)
                  puts stdout "set ::env($var) {$val};"
               }
               {cmd} {
                  set val $::env($var)
                  puts stdout "set $var=$val"
               }
               {perl} {
                  set val [charEscaped $::env($var) \']
                  puts stdout "\$ENV{'$var'} = '$val';"
               }
               {python} {
                  set val [charEscaped $::env($var) \']
                  puts stdout "os.environ\['$var'\] = '$val'"
               }
               {ruby} {
                  set val [charEscaped $::env($var) \']
                  puts stdout "ENV\['$var'\] = '$val'"
               }
               {lisp} {
                  set val [charEscaped $::env($var) \"]
                  puts stdout "(setenv \"$var\" \"$val\")"
               }
               {cmake} {
                  set val [charEscaped $::env($var) \"]
                  puts stdout "set(ENV{$var} \"$val\")"
               }
               {r} {
                  set val [charEscaped $::env($var) {\\'}]
                  puts stdout "Sys.setenv('$var'='$val')"
               }
            }
         }
         {del} {
            switch -- $::g_shellType {
               {csh} {
                  puts stdout "unsetenv $var;"
               }
               {sh} {
                  puts stdout "unset $var;"
               }
               {fish} {
                  puts stdout "set -e $var;"
               }
               {tcl} {
                  puts stdout "catch {unset ::env($var)};"
               }
               {cmd} {
                  puts stdout "set $var="
               }
               {perl} {
                  puts stdout "delete \$ENV{'$var'};"
               }
               {python} {
                  puts stdout "os.environ\['$var'\] = ''"
                  puts stdout "del os.environ\['$var'\]"
               }
               {ruby} {
                  puts stdout "ENV\['$var'\] = nil"
               }
               {lisp} {
                  puts stdout "(setenv \"$var\" nil)"
               }
               {cmake} {
                  puts stdout "unset(ENV{$var})"
               }
               {r} {
                  puts stdout "Sys.unsetenv('$var')"
               }
            }
         }
      }
   }

   foreach var [array names g_stateAliases] {
      switch -- $g_stateAliases($var) {
         {new} {
            set val $::g_Aliases($var)
            # convert $n in !!:n and $* in !* on csh (like on compat version)
            if {$::g_shellType eq "csh"} {
               regsub -all {([^\\]|^)\$([0-9]+)} $val {\1!!:\2} val
               regsub -all {([^\\]|^)\$\*} $val {\1!*} val
            }
            # unescape \$ after now csh-specific conversion is over
            regsub -all {\\\$} $val {$} val
            switch -- $::g_shellType {
               {csh} {
                  set val [charEscaped $val]
                  puts stdout "alias $var $val;"
               }
               {sh} {
                  set val [charEscaped $val]
                  puts stdout "alias $var=$val;"
               }
               {fish} {
                  set val [charEscaped $val]
                  puts stdout "alias $var $val;"
               }
               {cmd} {
                  puts stdout "doskey $var=$val"
               }
            }
         }
         {del} {
            switch -- $::g_shellType {
               {csh} {
                  puts stdout "unalias $var;"
               }
               {sh} {
                  puts stdout "unalias $var;"
               }
               {fish} {
                  puts stdout "functions -e $var;"
               }
               {cmd} {
                  puts stdout "doskey $var="
               }
            }
         }
      }
   }

   # preliminaries for x-resources stuff
   if {[array size g_newXResources] > 0 || [array size g_delXResources] > 0} {
      switch -- $::g_shellType {
         {python} {
            puts stdout "import subprocess"
         }
         {ruby} {
            puts stdout "require 'open3'"
         }
      }
   }

   # new x resources
   if {[array size g_newXResources] > 0} {
      # xrdb executable has already be verified in x-resource
      set xrdb [getCommandPath "xrdb"]
      foreach var [array names g_newXResources] {
         set val $g_newXResources($var)
         # empty val means that var is a file to parse
         if {$val eq ""} {
            switch -- $::g_shellType {
               {sh} - {csh} - {fish} {
                  puts stdout "$xrdb -merge $var;"
               }
               {tcl} {
                  puts stdout "exec $xrdb -merge $var;"
               }
               {perl} {
                  puts stdout "system(\"$xrdb -merge $var\");"
               }
               {python} {
                  set var [charEscaped $var \']
                  puts stdout "subprocess.Popen(\['$xrdb',\
                     '-merge', '$var'\])"
               }
               {ruby} {
                  set var [charEscaped $var \']
                  puts stdout "Open3.popen2('$xrdb -merge $var')"
               }
               {lisp} {
                  puts stdout "(shell-command-to-string \"$xrdb\
                     -merge $var\")"
               }
               {cmake} {
                  puts stdout "execute_process(COMMAND $xrdb -merge $var)"
               }
               {r} {
                  set var [charEscaped $var {\\'}]
                  puts stdout "system('$xrdb -merge $var')"
               }
            }
         } else {
            switch -- $::g_shellType {
               {sh} - {csh} - {fish} {
                  set var [charEscaped $var \"]
                  set val [charEscaped $val \"]
                  puts stdout "echo \"$var: $val\" | $xrdb -merge;"
               }
               {tcl} {
                  puts stdout "set XRDBPIPE \[open \"|$xrdb -merge\" r+\];"
                  set var [charEscaped $var \"]
                  set val [charEscaped $val \"]
                  puts stdout "puts \$XRDBPIPE \"$var: $val\";"
                  puts stdout "close \$XRDBPIPE;"
                  puts stdout "unset XRDBPIPE;"
               }
               {perl} {
                  puts stdout "open(XRDBPIPE, \"|$xrdb -merge\");"
                  set var [charEscaped $var \"]
                  set val [charEscaped $val \"]
                  puts stdout "print XRDBPIPE \"$var: $val\\n\";"
                  puts stdout "close XRDBPIPE;"
               }
               {python} {
                  set var [charEscaped $var \']
                  set val [charEscaped $val \']
                  puts stdout "subprocess.Popen(\['$xrdb', '-merge'\],\
                     stdin=subprocess.PIPE).communicate(input='$var:\
                     $val\\n')"
               }
               {ruby} {
                  set var [charEscaped $var \']
                  set val [charEscaped $val \']
                  puts stdout "Open3.popen2('$xrdb -merge') {|i,o,t| i.puts\
                     '$var: $val'}"
               }
               {lisp} {
                  puts stdout "(shell-command-to-string \"echo $var:\
                     $val | $xrdb -merge\")"
               }
               {cmake} {
                  set var [charEscaped $var \"]
                  set val [charEscaped $val \"]
                  puts stdout "execute_process(COMMAND echo \"$var: $val\"\
                     COMMAND $xrdb -merge)"
               }
               {r} {
                  set var [charEscaped $var {\\'}]
                  set val [charEscaped $val {\\'}]
                  puts stdout "system('$xrdb -merge', input='$var: $val')"
               }
            }
         }
      }
   }

   if {[array size g_delXResources] > 0} {
      set xrdb [getCommandPath "xrdb"]
      set xres_to_del {}
      foreach var [array names g_delXResources] {
         # empty val means that var is a file to parse
         if {$g_delXResources($var) eq ""} {
            # xresource file has to be parsed to find what resources
            # are declared there and need to be unset
            foreach fline [split [exec $xrdb -n load $var] "\n"] {
               lappend xres_to_del [lindex [split $fline ":"] 0]
            }
         } else {
            lappend xres_to_del $var
         }
      }

      # xresource strings are unset by emptying their value since there
      # is no command of xrdb that can properly remove one property
      switch -- $::g_shellType {
         {sh} - {csh} - {fish} {
            foreach var $xres_to_del {
               puts stdout "echo \"$var:\" | $xrdb -merge;"
            }
         }
         {tcl} {
            foreach var $xres_to_del {
               puts stdout "set XRDBPIPE \[open \"|$xrdb -merge\" r+\];"
               set var [charEscaped $var \"]
               puts stdout "puts \$XRDBPIPE \"$var:\";"
               puts stdout "close \$XRDBPIPE;"
               puts stdout "unset XRDBPIPE;"
            }
         }
         {perl} {
            foreach var $xres_to_del {
               puts stdout "open(XRDBPIPE, \"|$xrdb -merge\");"
               set var [charEscaped $var \"]
               puts stdout "print XRDBPIPE \"$var:\\n\";"
               puts stdout "close XRDBPIPE;"
            }
         }
         {python} {
            foreach var $xres_to_del {
               set var [charEscaped $var \']
               puts stdout "subprocess.Popen(\['$xrdb', '-merge'\],\
                  stdin=subprocess.PIPE).communicate(input='$var:\\n')"
            }
         }
         {ruby} {
            foreach var $xres_to_del {
               set var [charEscaped $var \']
               puts stdout "Open3.popen2('$xrdb -merge') {|i,o,t| i.puts\
                  '$var:'}"
            }
         }
         {lisp} {
            foreach var $xres_to_del {
               puts stdout "(shell-command-to-string \"echo $var: |\
                  $xrdb -merge\")"
            }
         }
         {cmake} {
            foreach var $xres_to_del {
               set var [charEscaped $var \"]
               puts stdout "execute_process(COMMAND echo \"$var:\"\
                  COMMAND $xrdb -merge)"
            }
         }
         {r} {
            foreach var $xres_to_del {
               set var [charEscaped $var {\\'}]
               puts stdout "system('$xrdb -merge', input='$var:')"
            }
         }
      }
   }

   if {[info exists ::g_changeDir]} {
      switch -- $::g_shellType {
         {sh} - {csh} - {fish} {
            puts stdout "cd '$::g_changeDir';"
         }
         {tcl} {
            puts stdout "cd \"$::g_changeDir\";"
         }
         {cmd} {
            puts stdout "cd $::g_changeDir"
         }
         {perl} {
            puts stdout "chdir '$::g_changeDir';"
         }
         {python} {
            puts stdout "os.chdir('$::g_changeDir')"
         }
         {ruby} {
            puts stdout "Dir.chdir('$::g_changeDir')"
         }
         {lisp} {
            puts stdout "(shell-command-to-string \"cd '$::g_changeDir'\")"
         }
         {r} {
            puts stdout "setwd('$::g_changeDir')"
         }
      }
      # cannot change current directory of cmake "shell"
   }

   # send content deferred during modulefile interpretation
   if {[info exists ::g_stdoutPuts]} {
      foreach putsArgs $::g_stdoutPuts {
         eval puts $putsArgs
         # check if a finishing newline will be needed after content sent
         if {[lindex $putsArgs 0] eq "-nonewline"} {
            set needPutsNl 1
         } else {
            set needPutsNl 0
         }
      }
      if {$needPutsNl} {
         puts stdout ""
      }
   }

   # return text value if defined even if error happened
   if {[info exists ::g_return_text]} {
      reportDebug "renderSettings: text value should be returned."
      renderText $::g_return_text
   } elseif {$::error_count > 0} {
      reportDebug "renderSettings: $::error_count error(s) detected."
      renderFalse
   } elseif {$::g_return_false} {
      reportDebug "renderSettings: false value should be returned."
      renderFalse
   } elseif {$has_rendered} {
      # finish with true statement if something has been put
      renderTrue
   }
}

proc renderAutoinit {} {
   reportDebug "renderAutoinit: called."

   # automatically detect which tclsh should be used for
   # future module commands
   set tclshbin [info nameofexecutable]

   # ensure script path is absolute
   set ::argv0 [getAbsolutePath $::argv0]

   switch -- $::g_shellType {
      {csh} {
         set pre_hi {set _histchars = $histchars; unset histchars;}
         set post_hi {set histchars = $_histchars; unset _histchars;}
         set pre_pr {set _prompt="$prompt"; set prompt="";}
         set post_pr {set prompt="$_prompt"; unset _prompt;}
         set eval_cmd "eval \"`$tclshbin $::argv0 $::g_shell \\!*:q`\";"
         set pre_ex {set _exit="$status";}
         set post_ex {test 0 = $_exit}

         set fdef "if ( \$?histchars && \$?prompt )\
alias module '$pre_hi $pre_pr $eval_cmd $pre_ex $post_hi $post_pr $post_ex' ;
if ( \$?histchars && ! \$?prompt )\
alias module '$pre_hi $eval_cmd $pre_ex $post_hi $post_ex' ;
if ( ! \$?histchars && \$?prompt )\
alias module '$pre_pr $eval_cmd $pre_ex $post_pr $post_ex' ;
if ( ! \$?histchars && ! \$?prompt ) alias module '$eval_cmd' ;"
      }
      {sh} {
         # Considering the diversity of ways local variables are handled
         # through the sh-variants ('local' known everywhere except on ksh,
         # 'typeset' known everywhere except on pure-sh, and on some systems
         # the pure-sh is in fact a 'ksh'), no local variables are defined and
         # these variables that should have been local are unset at the end

         # on zsh, word splitting should be enabled explicitly
         if {$::g_shell eq "zsh"} {
            set wsplit "="
         } else {
            set wsplit ""
         }
         # only redirect module from stderr to stdout when session is
         # attached to a terminal to avoid breaking non-terminal session
         # (scp, sftp, etc)
         if {[isStderrTty]} {
            set fname "_moduleraw"
         } else {
            set fname "module"
         }
         # build quarantine mechanism in module function
         # an empty runtime variable is set even if no corresponding
         # MODULES_RUNENV_* variable found, as var cannot be unset on
         # modified environment command-line
         set fdef "${fname}() {
   unset _mlre _mlIFS _mlshdbg;
   if \[ \"\$\{MODULES_SILENT_SHELL_DEBUG:-0\}\" = '1' \]; then
      case \"$-\" in
         *v*x*) set +vx; _mlshdbg='vx' ;;
         *v*) set +v; _mlshdbg='v' ;;
         *x*) set +x; _mlshdbg='x' ;;
         *) _mlshdbg='' ;;
      esac;
   fi;
   if \[ -n \"\${IFS+x}\" \]; then
      _mlIFS=\$IFS;
   fi;
   IFS=' ';
   for _mlv in \${${wsplit}MODULES_RUN_QUARANTINE:-}; do"
         append fdef {
      if [ "${_mlv}" = "${_mlv##*[!A-Za-z0-9_]}" -a "${_mlv}" = "${_mlv#[0-9]}" ]; then
         if [ -n "`eval 'echo ${'$_mlv'+x}'`" ]; then
            _mlre="${_mlre:-}${_mlv}_modquar='`eval 'echo ${'$_mlv'}'`' ";
         fi;
         _mlrv="MODULES_RUNENV_${_mlv}";
         _mlre="${_mlre:-}${_mlv}='`eval 'echo ${'$_mlrv':-}'`' ";
      fi;
   done;
   if [ -n "${_mlre:-}" ]; then}
         append fdef "\n      eval `eval \${${wsplit}_mlre}$tclshbin $::argv0\
$::g_shell '\"\$@\"'`;
   else
      eval `$tclshbin $::argv0 $::g_shell \"\$@\"`;
   fi;
   _mlstatus=\$?;\n"
         append fdef {   if [ -n "${_mlIFS+x}" ]; then
      IFS=$_mlIFS;
   else
      unset IFS;
   fi;
   if [ -n "${_mlshdbg:-}" ]; then
      set -$_mlshdbg;
   fi;
   unset _mlre _mlv _mlrv _mlIFS _mlshdbg;
   return $_mlstatus;}
         append fdef "\n};"
         if {[isStderrTty]} {
            append fdef "\nmodule() { _moduleraw \"\$@\" 2>&1; };"
         }
      }
      {fish} {
         if {[isStderrTty]} {
            set fdef "function _moduleraw\n"
         } else {
            set fdef "function module\n"
         }
         append fdef {   set -l _mlre ''; set -l _mlv; set -l _mlrv;
   for _mlv in (string split ' ' $MODULES_RUN_QUARANTINE)
      if string match -r '^[A-Za-z_][A-Za-z0-9_]*$' $_mlv >/dev/null
         if set -q $_mlv
            set _mlre $_mlre$_mlv"_modquar='$$_mlv' "
         end
         set _mlrv "MODULES_RUNENV_$_mlv"
         set _mlre "$_mlre$_mlv='$$_mlrv' "
      end
   end
   if [ -n "$_mlre" ]
      set _mlre "env $_mlre"
   end}
         # use "| source -" rather than "eval" to be able
         # to redirect stderr after stdout being evaluated
         append fdef "\n   eval \$_mlre $tclshbin $::argv0 $::g_shell\
            (string escape -- \$argv) | source -\n"
         if {[isStderrTty]} {
            append fdef {end
function module
   _moduleraw $argv ^&1
end}
         } else {
            append fdef {end}
         }
      }
      {tcl} {
         set fdef "proc module {args} {\n"
         append fdef {   set _mlre {};
   if {[info exists ::env(MODULES_RUN_QUARANTINE)]} {
      foreach _mlv [split $::env(MODULES_RUN_QUARANTINE) " "] {
         if {[regexp {^[A-Za-z_][A-Za-z0-9_]*$} $_mlv]} {
            if {[info exists ::env($_mlv)]} {
               lappend _mlre "${_mlv}_modquar=$::env($_mlv)"
            }
            set _mlrv "MODULES_RUNENV_${_mlv}"
            if {[info exists ::env($_mlrv)]} {
               lappend _mlre "${_mlv}=$::env($_mlrv)"
            } else {
               lappend _mlre "${_mlv}="
            }
         }
      }
      if {[llength $_mlre] > 0} {
         set _mlre [linsert $_mlre 0 "env"]
      }
   }
   set _mlstatus 1;}
         append fdef "\n   catch {eval exec \$_mlre \"$tclshbin\"\
            \"$::argv0\" \"$::g_shell\" \$args 2>@stderr} script\n"
         append fdef {   eval $script;
   return $_mlstatus}
         append fdef "\n}"
      }
      {cmd} {
         reportErrorAndExit "No autoinit mode available for 'cmd' shell"
      }
      {perl} {
         set fdef "sub module {\n"
         append fdef {   my $_mlre = '';
   if (defined $ENV{'MODULES_RUN_QUARANTINE'}) {
      foreach my $_mlv (split(' ', $ENV{'MODULES_RUN_QUARANTINE'})) {
         if ($_mlv =~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
            if (defined $ENV{$_mlv}) {
               $_mlre .= "${_mlv}_modquar='$ENV{$_mlv}' ";
            }
            my $_mlrv = "MODULES_RUNENV_$_mlv";
            $_mlre .= "$_mlv='$ENV{$_mlrv}' ";
        }
      }
      if ($_mlre ne "") {
         $_mlre = "env $_mlre";
      }
   }
   my $args = '';
   if (@_ > 0) {
      $args = '"' . join('" "', @_) . '"';
   }
   my $_mlstatus = 1;}
         append fdef "\n   eval `\${_mlre}$tclshbin $::argv0 perl \$args`;\n"
         append fdef {   return $_mlstatus;}
         append fdef "\n}"
      }
      {python} {
         set fdef {import re, subprocess
def module(*arguments):
   _mlre = os.environ.copy()
   if 'MODULES_RUN_QUARANTINE' in os.environ:
      for _mlv in os.environ['MODULES_RUN_QUARANTINE'].split():
         if re.match('^[A-Za-z_][A-Za-z0-9_]*$', _mlv):
            if _mlv in os.environ:
               _mlre[_mlv + '_modquar'] = os.environ[_mlv]
            _mlrv = 'MODULES_RUNENV_' + _mlv
            if _mlrv in os.environ:
               _mlre[_mlv] = os.environ[_mlrv]
            else:
               _mlre[_mlv] = ''
   _mlstatus = True}
         append fdef "\n   exec(subprocess.Popen(\['$tclshbin',\
            '$::argv0', 'python'\] + list(arguments),\
            stdout=subprocess.PIPE, env=_mlre).communicate()\[0\])\n"
         append fdef {   return _mlstatus}
      }
      {ruby} {
         set fdef {class ENVModule
   def ENVModule.module(*args)
      _mlre = ''
      if ENV.has_key?('MODULES_RUN_QUARANTINE') then
         ENV['MODULES_RUN_QUARANTINE'].split(' ').each do |_mlv|
            if _mlv =~ /^[A-Za-z_][A-Za-z0-9_]*$/ then
               if ENV.has_key?(_mlv) then
                  _mlre << _mlv + "_modquar='" + ENV[_mlv].to_s + "' "
               end
               _mlrv = 'MODULES_RUNENV_' + _mlv
               _mlre << _mlv + "='" + ENV[_mlrv].to_s + "' "
            end
         end
         unless _mlre.empty?
            _mlre = 'env ' + _mlre
         end
      end
      if args[0].kind_of?(Array) then
         args = args[0]
      end
      if args.length == 0 then
         args = ''
      else
         args = "\"#{args.join('" "')}\""
      end
      _mlstatus = true}
         append fdef "\n      eval `#{_mlre}$tclshbin $::argv0 ruby #{args}`\n"
         append fdef {      return _mlstatus
   end
end}
      }
      {lisp} {
         reportErrorAndExit "lisp mode autoinit not yet implemented"
      }
      {cmake} {
         set pre_exec "\n      execute_process(COMMAND \${_mlre} $tclshbin\
            $::argv0 cmake "
         set post_exec "\n         OUTPUT_FILE \${tempfile_name})\n"
         set fdef {function(module)
   cmake_policy(SET CMP0007 NEW)
   set(_mlre "")
   if(DEFINED ENV{MODULES_RUN_QUARANTINE})
      string(REPLACE " " ";" _mlv_list "$ENV{MODULES_RUN_QUARANTINE}")
      foreach(_mlv ${_mlv_list})
         if(${_mlv} MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
            if(DEFINED ENV{${_mlv}})
               set(_mlre "${_mlre}${_mlv}_modquar=$ENV{${_mlv}};")
            endif()
            set(_mlrv "MODULES_RUNENV_${_mlv}")
            set(_mlre "${_mlre}${_mlv}=$ENV{${_mlrv}};")
        endif()
      endforeach()
      if (NOT "${_mlre}" STREQUAL "")
         set(_mlre "env;${_mlre}")
      endif()
   endif()
   set(_mlstatus TRUE)
   execute_process(COMMAND mktemp -t moduleinit.cmake.XXXXXXXXXXXX
      OUTPUT_VARIABLE tempfile_name
      OUTPUT_STRIP_TRAILING_WHITESPACE)
   if(${ARGC} EQUAL 1)}
            # adapt command definition depending on the number of args to be
            # able to pass to some extend (<5 args) empty string element to
            # modulecmd (no other way as empty element in ${ARGV} are skipped
            append fdef "$pre_exec\"\${ARGV0}\"$post_exec"
            append fdef {   elseif(${ARGC} EQUAL 2)}
            append fdef "$pre_exec\"\${ARGV0}\" \"\${ARGV1}\"$post_exec"
            append fdef {   elseif(${ARGC} EQUAL 3)}
            append fdef "$pre_exec\"\${ARGV0}\" \"\${ARGV1}\"\
               \"\${ARGV2}\"$post_exec"
            append fdef {   elseif(${ARGC} EQUAL 4)}
            append fdef "$pre_exec\"\${ARGV0}\" \"\${ARGV1}\"\
               \"\${ARGV2}\" \"\${ARGV3}\"$post_exec"
            append fdef {   else()}
            append fdef "$pre_exec\${ARGV}$post_exec"
            append fdef {   endif()
   if(EXISTS ${tempfile_name})
      include(${tempfile_name})
      file(REMOVE ${tempfile_name})
   endif()
   set(module_result ${_mlstatus} PARENT_SCOPE)
endfunction(module)}
      }
      {r} {
         set fdef "module <- function(...){\n"
         append fdef {   mlre <- ''
   if (!is.na(Sys.getenv('MODULES_RUN_QUARANTINE', unset=NA))) {
      for (mlv in strsplit(Sys.getenv('MODULES_RUN_QUARANTINE'), ' ')[[1]]) {
         if (grepl('^[A-Za-z_][A-Za-z0-9_]*$', mlv)) {
            if (!is.na(Sys.getenv(mlv, unset=NA))) {
               mlre <- paste0(mlre, mlv, "_modquar='", Sys.getenv(mlv), "' ")
            }
            mlrv <- paste0('MODULES_RUNENV_', mlv)
            mlre <- paste0(mlre, mlv, "='", Sys.getenv(mlrv), "' ")
         }
      }
      if (mlre != '') {
         mlre <- paste0('env ', mlre)
      }
   }
   arglist <- as.list(match.call())
   arglist[1] <- 'r'
   args <- paste0('"', paste0(arglist, collapse='" "'), '"')}
         append fdef "\n   cmd <- paste(mlre, '$tclshbin', '$::argv0', args,\
            sep=' ')\n"
         append fdef {   mlstatus <- TRUE
   hndl <- pipe(cmd)
   eval(expr = parse(file=hndl))
   close(hndl)
   invisible(mlstatus)}
         append fdef "\n}"

      }
   }

   # output function definition
   puts stdout $fdef
}

proc cacheCurrentModules {} {
   # parse loaded modules information only once, global arrays are updated
   # afterwards when module commands update loaded modules state
   if {![info exists ::g_lm_info_cached]} {
      # mark specific as well as generic modules as loaded
      set i 0
      set modfilelist [getLoadedModuleFileList]
      set modlist [getLoadedModuleList]

      if {[llength $modlist] == [llength $modfilelist]} {
         foreach mod $modlist {
            setLoadedModule $mod [lindex $modfilelist $i]
            incr i
         }

         set ::g_lm_info_cached 1
         reportDebug "cacheCurrentModules: $i loaded"
      } else {
         reportErrorAndExit "Loaded environment state is inconsistent\n \
            LOADEDMODULES=$modlist\n  _LMFILES_=$modfilelist"
      }
   }
}

# This proc resolves module aliases or version aliases to the real module name
# and version.
proc resolveModuleVersionOrAlias {name} {
   if {[info exists ::g_moduleResolved($name)]} {
      set ret $::g_moduleResolved($name)
   } else {
      set ret $name
   }

   reportDebug "resolveModuleVersionOrAlias: '$name' resolved to '$ret'"

   return $ret
}

proc charEscaped {str {charlist { \\\t\{\}|<>!;#^$&*"'`()}}} {
   return [regsub -all "\(\[$charlist\]\)" $str {\\\1}]
}

proc charUnescaped {str {charlist { \\\t\{\}|<>!;#^$&*"'`()}}} {
   return [regsub -all "\\\\\(\[$charlist\]\)" $str {\1}]
}

# find command path and remember it
proc getCommandPath {cmd} {
   return [lindex [auto_execok $cmd] 0]
}

# find then run command or raise error if command not found
proc runCommand {cmd args} {
   set cmdpath [getCommandPath $cmd]
   if {$cmdpath eq ""} {
      error "WARNING: Command '$cmd' cannot be found"
   } else {
      return [eval exec $cmdpath $args]
   }
}

proc getAbsolutePath {path} {
   # currently executing a modulefile or rc, so get the directory of this file
   if {$::ModulesCurrentModulefile ne ""} {
      set curdir [file dirname $::ModulesCurrentModulefile]
   # elsewhere get module command current working directory
   } else {
      # register pwd at first call
      if {![info exists ::cwd]} {
         set ::cwd [pwd]
      }
      set curdir $::cwd
   }

   # empty result if empty path
   if {$path eq ""} {
      set abspath {}
   } else {
      set abslist {}
      # get a first version of the absolute path by joining the current
      # working directory to the given path. if given path is already absolute
      # 'file join' will not break it as $curdir will be ignored as soon a
      # beginning '/' character is found on $path. this first pass also clean
      # extra '/' character. then each element of the path is analyzed to
      # clear "." and ".." components.
      foreach elt [file split [file join $curdir $path]] {
         if {$elt eq ".."} {
            # skip ".." element if it comes after root element, remove last
            # element elsewhere
            if {[llength $abslist] > 1} {
               set abslist [lreplace $abslist end end]
            }
         # skip any "." element
         } elseif {$elt ne "."} {
            lappend abslist $elt
         }
      }
      set abspath [eval file join $abslist]
   }

   # return cleaned absolute path
   return $abspath
}

# split string while ignore any separator character that is espaced
proc psplit {str sep} {
   set previdx -1
   set idx [string first $sep $str]
   while {$idx != -1} {
      # look ahead if found separator is escaped
      if {[string index $str [expr {$idx-1}]] ne "\\"} {
         # unescape any separator character when adding to list
         lappend res [charUnescaped [string range $str [expr {$previdx+1}]\
            [expr {$idx-1}]] $sep]
         set previdx $idx
      }
      set idx [string first $sep $str [expr {$idx+1}]]
   }

   lappend res [charUnescaped [string range $str [expr {$previdx+1}] end]\
      $sep]

   return $res
}

# join list while escape any character equal to separator
proc pjoin {lst sep} {
   set res ""

   foreach elt $lst {
      # preserve empty entries
      if {[info exists not_first]} {
         append res $sep
      } else {
         set not_first 1
      }
      # escape any separator character when adding to string
      append res [charEscaped $elt $sep]
   }

   return $res
}

# provide a lreverse proc for Tcl8.4 and earlier
if {[info commands lreverse] eq ""} {
   proc lreverse {l} {
      set r [list]
      for {set i [expr {[llength $l] - 1}]} {$i >= 0} {incr i -1} {
         lappend r [lindex $l $i]
      }
      return $r
   }
}

# provide a lassign proc for Tcl8.4 and earlier
if {[info commands lassign] eq ""} {
   proc lassign {values args} {
      uplevel 1 [list foreach $args [linsert $values end {}] break]
      lrange $values [llength $args] end
   }
}

proc replaceFromList {list1 item {item2 {}}} {
    while {[set xi [lsearch -exact $list1 $item]] >= 0} {
       if {[string length $item2] == 0} {
          set list1 [lreplace $list1 $xi $xi]
       } else {
          set list1 [lreplace $list1 $xi $xi $item2]
       }
    }

    return $list1
}

proc parseAccessIssue {modfile} {
   # retrieve and return access issue message
   if {[regexp {POSIX .* \{(.*)\}$} $::errorCode match errMsg]} {
      return "[string totitle $errMsg] on '$modfile'"
   } else {
      return "Cannot access '$modfile'"
   }
}

proc checkValidModule {modfile} {

   reportDebug "checkValidModule: $modfile"

   # use cached result
   if {[info exists ::g_modfileValid($modfile)]} {
      return $::g_modfileValid($modfile)
   } else {
      # Check for valid module
      if {[catch {
         set fid [open $modfile r]
         set fheader [read $fid 8]
         close $fid
      }]} {
         set check_valid "accesserr"
         set check_msg [parseAccessIssue $modfile]
      } else {
         if {$fheader eq "\#%Module"} {
            set check_valid "true"
            set check_msg ""
         } else {
            set check_valid "invalid"
            set check_msg "Magic cookie '#%Module' missing"
         }
      }

      # cache result at first query
      return [set ::g_modfileValid($modfile) [list $check_valid $check_msg]]
   }
}

# get file modification time, cache it at first query, use cache afterward
proc getFileMtime {fpath} {
   if {[info exists ::g_fileMtime($fpath)]} {
      return $::g_fileMtime($fpath)
   } else {
      return [set ::g_fileMtime($fpath) [file mtime $fpath]]
   }
}

proc readModuleContent {modfile {report_read_issue 0} {must_have_cookie 1}} {
   reportDebug "readModuleContent: $modfile"

   # read file
   if {[catch {
      set fid [open $modfile r]
      set fdata [read $fid]
      close $fid
   } errMsg ]} {
      if {$report_read_issue} {
         reportError [parseAccessIssue $modfile]
      }
      return {}
   }

   # check module validity if magic cookie is mandatory
   if {[string first "\#%Module" $fdata] == 0 || !$must_have_cookie} {
      return $fdata
   } else {
      reportInternalBug "Magic cookie '#%Module' missing" $modfile
      return {}
   }
}

# If given module maps to default or other symbolic versions, a list of
# those versions is returned. This takes module/version as an argument.
proc getVersAliasList {mod} {
   if {[info exists ::g_symbolHash($mod)]} {
      set tag_list $::g_symbolHash($mod)
   } else {
      set tag_list {}
   }

   reportDebug "getVersAliasList: '$mod' has tag list '$tag_list'"

   return $tag_list
}

# finds all module-related files matching mod in the module path dir
proc findModules {dir {mod {}} {fetch_mtime 0} {fetch_hidden 0}} {
   reportDebug "findModules: finding '$mod' in $dir\
      (fetch_mtime=$fetch_mtime, fetch_hidden=$fetch_hidden)"

   # use catch protection to handle non-readable and non-existent dir
   if {[catch {
      set full_list [glob -nocomplain "$dir/$mod"]
   }]} {
      return {}
   }

   # remove trailing / needed on some platforms
   regsub {\/$} $full_list {} full_list

   array set mod_list {}
   for {set i 0} {$i < [llength $full_list]} {incr i 1} {
      set element [lindex $full_list $i]
      set tag_list {}

      set tail [file tail $element]
      set modulename [getModuleNameFromModulepath $element $dir]
      set add_ref_to_parent 0
      if {[file isdirectory $element]} {
         if {![info exists ::ignoreDir($tail)]} {
            # try then catch any issue rather than test before trying
            # workaround 'glob -nocomplain' which does not return permission
            # error on Tcl 8.4, so we need to avoid registering issue if
            # raised error is about a no match
            set treat_dir 1
            if {[catch {set elt_list [glob "$element/*"]} errMsg]} {
               if {$errMsg eq "no files matched glob pattern\
                  \"$element/*\""} {
                  set elt_list {}
               } else {
                  set mod_list($modulename) [list "accesserr"\
                     [parseAccessIssue $element] $element]
                  set treat_dir 0
               }
            }
            if {$treat_dir} {
               set mod_list($modulename) [list "directory"]
               # Add each element in the current directory to the list
               if {[file readable $element/.modulerc]} {
                  lappend full_list $element/.modulerc
               }
               if {[file readable $element/.version]} {
                  lappend full_list $element/.version
               }
               if {[llength $elt_list] > 0} {
                  set full_list [concat $full_list $elt_list]
               }
               # search for hidden files if asked
               if {$fetch_hidden} {
                  foreach elt [glob -nocomplain -types hidden -directory\
                     $element -tails "*"] {
                     switch -- $elt {
                        {.modulerc} - {.version} - {.} - {..} { }
                        default {
                           lappend full_list $element/$elt
                           set hidden_list($element/$elt) 1
                        }
                     }
                  }
               }
               set add_ref_to_parent 1
            }
         }
      } else {
         switch -glob -- $tail {
            {.modulerc} {
               set mod_list($modulename) [list "modulerc"]
            }
            {.version} {
               set mod_list($modulename) [list "modulerc"]
            }
            {*~} - {*,v} - {\#*\#} { }
            default {
               lassign [checkValidModule $element] check_valid check_msg
               switch -- $check_valid {
                  {true} {
                     if {$fetch_mtime} {
                        set mtime [getFileMtime $element]
                     } else {
                        set mtime {}
                     }
                     set mod_list($modulename) [list "modulefile" $mtime]
                     # if modfile hidden, do not reference it in parent list
                     if {$fetch_hidden && [info exists\
                        hidden_list($element)]} {
                        set add_ref_to_parent 0
                     } else {
                        set add_ref_to_parent 1
                     }
                  }
                  default {
                     # register check error and relative message to get it in
                     # case of direct access of this module element, but no
                     # registering in parent directory structure as element
                     # is not valid
                     set mod_list($modulename) [list $check_valid $check_msg\
                        $element]
                  }
               }
            }
         }
      }

      # add reference to parent structure
      if {$add_ref_to_parent} {
         set parentname [file dirname $modulename]
         if {[info exists mod_list($parentname)]} {
            lappend mod_list($parentname) $tail
         }
      }
   }

   reportDebug "findModules: found [array names mod_list]"

   return [array get mod_list]
}

proc getModules {dir {mod {}} {fetch_mtime 0} {search {}} {fetch_hidden 0}} {
   global g_sourceAlias g_sourceVersion g_sourceVirtual g_resolvedPath
   global g_rcAlias g_moduleAlias g_rcVersion g_moduleVersion
   global g_rcVirtual g_moduleVirtual

   reportDebug "getModules: get '$mod' in $dir (fetch_mtime=$fetch_mtime,\
      search=$search, fetch_hidden=$fetch_hidden)"

   # if search for global or user rc alias only, no dir lookup is performed
   # and aliases from g_rcAlias are returned
   if {[lsearch -exact $search "rc_alias_only"] >= 0} {
      set add_rc_defs 1
      array set found_list {}
   } else {
      # find modules by searching with first path element if mod is a deep
      # modulefile (elt1/etl2/vers) in order to catch all .modulerc and
      # .version files of module-related parent directories in case we need
      # to translate an alias or a version
      set parentlist [split $mod "/"]
      set findmod [lindex $parentlist 0]
      # if searched mod is an empty or flat element append wildcard character
      # to match anything starting with mod
      if {[lsearch -exact $search "wild"] >= 0 &&\
         [llength $parentlist] <= 1} {
         append findmod "*"
      }
      # add alias/version definitions from global or user rc to result
      if {[lsearch -exact $search "rc_defs_included"] >= 0} {
         set add_rc_defs 1
      } else {
         set add_rc_defs 0
      }
      if {!$fetch_hidden} {
         set fetch_hidden [isModuleHidden $mod]
         reportDebug "getModules: is '$mod' requiring hidden search\
            ($fetch_hidden)"
      }
      array set found_list [findModules $dir $findmod $fetch_mtime\
         $fetch_hidden]
   }

   array set dir_list {}
   array set mod_list {}
   foreach elt [lsort [array names found_list]] {
      if {[lindex $found_list($elt) 0] eq "modulerc"} {
         # push name to be found by module-alias and version
         pushSpecifiedName $elt
         pushModuleName $elt
         execute-modulerc $dir/$elt
         popModuleName
         popSpecifiedName
      # add other entry kind to the result list
      } elseif {[string match $mod* $elt]} {
         set mod_list($elt) $found_list($elt)
         # list dirs to rework their definition at the end
         if {[lindex $found_list($elt) 0] eq "directory"} {
            set dir_list($elt) 1
         }
      }
   }

   # add versions found when parsing .version or .modulerc files in this
   # directory (skip versions not registered from this directory except if
   # global or user rc definitions should be included)) if they match passed
   # $mod (as for regular modulefiles)
   foreach vers [array names g_moduleVersion -glob $mod*] {
      set versmod $g_moduleVersion($vers)
      if {($dir ne "" && [string first "$dir/" $g_sourceVersion($vers)] == 0)\
         || ($add_rc_defs && [info exists g_rcVersion($vers)])} {
         set mod_list($vers) [list "version" $versmod]
      }
      # no reference add to parent directory structure as versions are virtual

      # add the target of symbolic versions found when parsing .version or
      # .modulerc files if these symbols match passed $mod (as for regular
      # modulefiles). modulefile target of these version symbol should have
      # been found previously to be added
      if {![info exists mod_list($versmod)]} {
         # exception made to hidden modulefile target which should not be
         # found previously as not searched (except if we already look for
         # hidden modules). in case symbolic version matches passed $mod
         # look for this hidden target
         if {$mod eq $vers && !$fetch_hidden && [isModuleHidden $versmod]} {
            array set found_list [findModules $dir $versmod $fetch_mtime 1]
         }

         # symbolic version targets a modulefile most of the time
         if {[info exists found_list($versmod)]} {
            set mod_list($versmod) $found_list($versmod)
         # but sometimes they may target an alias
         } elseif {[info exists g_moduleAlias($versmod)]} {
            lappend matching_versalias $versmod
         # or a virtual module
         } elseif {[info exists g_moduleVirtual($versmod)]} {
            lappend matching_versvirt $versmod
         }
      }
   }

   # add aliases found when parsing .version or .modulerc files in this
   # directory (skip aliases not registered from this directory except if
   # global or user rc definitions should be included) if they match passed
   # $mod (as for regular modulefiles) or if a symbolic versions targeting
   # alias match passed $mod
   set matching_alias [array names g_moduleAlias -glob $mod*]
   if {[info exists matching_versalias]} {
      foreach versalias $matching_versalias {
         if {[lsearch -exact $matching_alias $versalias] == -1} {
            lappend matching_alias $versalias
         }
      }
   }
   foreach alias $matching_alias {
      if {($dir ne "" && [string first "$dir/" $g_sourceAlias($alias)] == 0)\
         || ($add_rc_defs && [info exists g_rcAlias($alias)])} {
         set mod_list($alias) [list "alias" $g_moduleAlias($alias)]

         # in case alias overwrites a directory definition
         if {[info exists dir_list($alias)]} {
             unset dir_list($alias)
         }

         # add reference to this alias version in parent structure
         set parentname [file dirname $alias]
         if {[info exists mod_list($parentname)]} {
            lappend mod_list($parentname) [file tail $alias]
         } else {
            # add reference to orphan list if dir does not exist may be added
            # below if dir is virtually set by a virtual deep module
            lappend orphan_list($parentname) [file tail $alias]
         }
      }
   }

   # add virtual mods found when parsing .version or .modulerc files in this
   # directory (skip virtual mods not registered from this directory except if
   # global or user rc definitions should be included) if they match passed
   # $mod (as for regular modulefiles) or if a symbolic versions targeting
   # virtual mod match passed $mod
   set matching_virtual [array names g_moduleVirtual -glob $mod*]
   if {[info exists matching_versvirt]} {
      foreach versvirt $matching_versvirt {
         if {[lsearch -exact $matching_virtual $versvirt] == -1} {
            lappend matching_virtual $versvirt
         }
      }
   }
   foreach virt $matching_virtual {
      if {($dir ne "" && [string first "$dir/" $g_sourceVirtual($virt)] == 0)\
         || ($add_rc_defs && [info exists g_rcVirtual($virt)])} {
         lassign [checkValidModule $g_moduleVirtual($virt)] check_valid\
            check_msg
         switch -- $check_valid {
            {true} {
               if {$fetch_mtime} {
                  set mtime [getFileMtime $g_moduleVirtual($virt)]
               } else {
                  set mtime {}
               }
               # set mtime at index 1 like a modulefile entry
               set mod_list($virt) [list "virtual" $mtime\
                  $g_moduleVirtual($virt)]

               set add_ref_to_parent 1
            }
            default {
               # register check error and relative message to get it in
               # case of direct access of this module element, but no
               # registering in parent directory structure as element
               # is not valid
               set mod_list($virt) [list $check_valid $check_msg\
                  $g_moduleVirtual($virt)]

               # no reference to parent list
               set add_ref_to_parent 0
            }
         }

         # in case virtual mod overwrites a directory definition
         if {[info exists dir_list($virt)]} {
             unset dir_list($virt)
         }

         # add reference to this virtual mod in parent structure
         if {$add_ref_to_parent} {
            set parentname [file dirname $virt]
            set elt [file tail $virt]

            # initialize virtual parent structure if it does not exist
            if {![info exists mod_list($parentname)]} {
               # loop until reaching an existing or a top entry
               while {![info exists mod_list($parentname)]\
                  && $parentname ne "."} {
                  # create virtual directory entry
                  set mod_list($parentname) [list "directory" $elt]
                  set dir_list($parentname) 1

                  set elt [file tail $parentname]
                  set parentname [file dirname $parentname]
               }
               # add reference to reached existing entry
               if {[info exists mod_list($parentname)]} {
                  lappend mod_list($parentname) $elt
               }
            } else {
               lappend mod_list($parentname) $elt
            }
         }
      }
   }

   # integrate aliases defined in orphan directories if these dirs have been
   # virtually created by a virtual module reference
   foreach dir [array names orphan_list] {
      if {[info exists mod_list($dir)]} {
         set mod_list($dir) [concat $mod_list($dir) $orphan_list($dir)]
      }
   }

   # work on directories integrated in the result list by registering
   # default element in this dir and list of all child elements dictionary
   # sorted, so last element in dir is also last element in this list
   # this treatment happen at the end to find all directory entries in
   # result list (alias and virtual included)
   foreach dir [lsort [array names dir_list]] {
      set elt_list [lsort -dictionary [lrange $mod_list($dir) 1 end]]
      # remove dir from list if it is empty
      if {[llength $elt_list] == 0} {
         unset mod_list($dir)
         # rework upper directories content if registered
         while {[set par_dir [file dirname $dir]] ne "."\
            && [info exists mod_list($par_dir)]} {
            set dir_name [file tail $dir]
            set dir $par_dir
            # quit if something has overwritten the directory definition
            if {[lindex $mod_list($dir) 0] ne "directory"} {
               break
            }
            # get upper dir content without empty dir (as dir_list is sorted
            # parent dir information have already been consolidated)
            set elt_list [lsearch -all -inline -not -exact [lrange\
               $mod_list($dir) 2 end] $dir_name]
            # remove also parent dir if it becomes empty
            if {[llength $elt_list] == 0} {
               unset mod_list($dir)
            } else {
               # change default by last element if empty dir was default
               set dfl_elt [lindex $mod_list($dir) 1]
               if {$dfl_elt eq $dir_name} {
                  set dfl_elt [lindex $elt_list end]
               }
               set mod_list($dir) [concat [list "directory" $dfl_elt]\
                  $elt_list]
               # no need to update upper directory as this one persists
               break
            }
         }
      } else {
         # get default element (defined or implicit)
         if {[info exists g_resolvedPath($dir)]} {
            set dfl_elt [file tail $g_resolvedPath($dir)]
         } else {
            set dfl_elt [lindex $elt_list end]
         }
         set mod_list($dir) [concat [list "directory" $dfl_elt] $elt_list]
      }
   }

   reportDebug "getModules: got [array names mod_list]"

   return [array get mod_list]
}

# Finds all module versions for mod in the module path dir
proc listModules {dir mod {show_flags {1}} {filter {}} {search "wild"}} {
   reportDebug "listModules: get '$mod' in $dir\
      (show_flags=$show_flags, filter=$filter, search=$search)"

   # report flags for directories and modulefiles depending on show_flags
   # procedure argument and global variables
   if {$show_flags && $::flag_default_mf} {
      set show_flags_mf 1
   } else {
      set show_flags_mf 0
   }
   if {$show_flags && $::flag_default_dir} {
      set show_flags_dir 1
   } else {
      set show_flags_dir 0
   }
   if {$show_flags && $::show_modtimes} {
      set show_mtime 1
   } else {
      set show_mtime 0
   }

   # get module list
   # as we treat a full directory content do not exit on an error
   # raised from one modulerc file
   array set mod_list [getModules $dir $mod $show_mtime $search]

   # prepare results for display
   set clean_list {}
   foreach elt [array names mod_list] {
      set elt_type [lindex $mod_list($elt) 0]

      set add_to_clean_list 1
      if {$filter ne ""} {
         # only analyze directories or modulefile at the root in case of
         # result filtering. depending on filter kind the selection of the
         # modulefile to display will be made using the definition
         # information of its upper directory
         if {$elt_type eq "directory"} {
            switch -- $filter {
               {onlydefaults} {
                  set elt_vers [lindex $mod_list($elt) 1]
               }
               {onlylatest} {
                  set elt_vers [lindex $mod_list($elt) end]
               }
            }
            # switch to selected modulefile to display
            append elt "/$elt_vers"
            # verify it exists elsewhere skip result for this directory
            if {![info exists mod_list($elt)]} {
               continue
            }
            set elt_type [lindex $mod_list($elt) 0]
            # skip if directory selected, will be looked at in a next round
            if {$elt_type eq "directory"} {
               set add_to_clean_list 0
            }
         } elseif {[file dirname $elt] ne "."} {
            set add_to_clean_list 0
         }

         if {$add_to_clean_list} {
            set tag_list [getVersAliasList $elt]
         }
      } else {
         set tag_list [getVersAliasList $elt]
         # do not add a dir if it does not hold tags
         if {$elt_type eq "directory" && [llength $tag_list] == 0} {
            set add_to_clean_list 0
         }
      }

      if {$add_to_clean_list} {
         switch -- $elt_type {
            {directory} {
               if {$show_flags_dir} {
                  if {$show_mtime} {
                     lappend clean_list [format "%-40s%-20s" $elt\
                        [join $tag_list ":"]]
                  } else {
                     lappend clean_list [join [list $elt "("\
                        [join $tag_list ":"] ")"] {}]
                  }
               } else {
                  lappend clean_list $elt
               }
            }
            {modulefile} - {virtual} {
               if {$show_mtime} {
                  # add to display file modification time in addition
                  # to potential tags
                  lappend clean_list [format "%-40s%-20s%19s" $elt\
                     [join $tag_list ":"]\
                     [clock format [lindex $mod_list($elt) 1]\
                     -format "%Y/%m/%d %H:%M:%S"]]
               } elseif {$show_flags_mf && [llength $tag_list] > 0} {
                  lappend clean_list [join [list $elt "("\
                     [join $tag_list ":"] ")"] {}]
               } else {
                  lappend clean_list $elt
               }
            }
            {alias} {
               if {$show_mtime} {
                  lappend clean_list [format "%-40s%-20s"\
                     "$elt -> [lindex $mod_list($elt) 1]"\
                     [join $tag_list ":"]]
               } elseif {$show_flags_mf} {
                  lappend tag_list "@"
                  lappend clean_list [join [list $elt "("\
                     [join $tag_list ":"] ")"] {}]
               } else {
                  lappend clean_list $elt
               }
            }
         }
         # ignore "version" entries as symbolic version are treated
         # along to their relative modulefile not independently
      }
   }

   # always dictionary-sort results
   set clean_list [lsort -dictionary $clean_list]
   reportDebug "listModules: Returning $clean_list"

   return $clean_list
}

proc showModulePath {} {
   reportDebug "showModulePath"

   set modpathlist [getModulePathList]
   if {[llength $modpathlist] > 0} {
      report "Search path for module files (in search order):"
      foreach path $modpathlist {
         report "  $path"
      }
   } else {
      reportWarning "No directories on module search path"
   }
}

proc displayTableHeader {args} {
   set first 1
   foreach title $args {
      if {$first} {
         set first 0
         if {[llength $args] > 2} {
            set col_len 39
         } else {
            set col_len 59
         }
      } else {
         set col_len 19
      }

      set col "- $title "
      append col [string repeat {-} [expr {$col_len - [string length $col]}]]
      lappend col_list $col
   }

   report [join $col_list "."]
}

proc displaySeparatorLine {{title {}}} {
   set tty_cols [getTtyColumns]
   if {$title eq ""} {
      # adapt length if screen width is very small
      set max_rep 67
      if {$tty_cols > $max_rep} {
         set rep $max_rep
      } else {
         set rep $tty_cols
      }
      report "[string repeat {-} $rep]"
   } else {
      set len  [string length $title]
      # max expr function is not supported in Tcl8.4 and earlier
      if {[set lrep [expr {($tty_cols - $len - 2)/2}]] < 1} {
         set lrep 1
      }
      if {[set rrep [expr {$tty_cols - $len - 2 - $lrep}]] < 1} {
         set rrep 1
      }
      report "[string repeat {-} $lrep] $title [string repeat {-} $rrep]"
   }
}

# get a list of elements and print them in a column or in a
# one-per-line fashion
proc displayElementList {header hstyle one_per_line display_idx args} {
   set elt_cnt [llength $args]
   reportDebug "displayElementList: header=$header, hstyle=$hstyle,\
      elt_cnt=$elt_cnt, one_per_line=$one_per_line, display_idx=$display_idx"

   # end proc if no element are to print
   if {$elt_cnt == 0} {
      return
   }

   # display header if any provided
   if {$header ne "noheader"} {
      # if list already displayed, separate with a blank line before header
      if {![info exists ::g_eltlist_disp]} {
         set ::g_eltlist_disp 1
      } else {
         report ""
      }

      if {$hstyle eq "sepline"} {
         displaySeparatorLine $header
      } else {
         report "$header:"
      }
   }

   # display one element per line
   if {$one_per_line} {
      if {$display_idx} {
         set idx 1
         foreach elt $args {
            append displist [format "%2d) %s " $idx $elt] "\n"
            incr idx
         }
      } else {
         append displist [join $args "\n"] "\n"
      }
   # elsewhere display elements in columns
   } else {
      if {$display_idx} {
         # save room for numbers and spacing: 2 digits + ) + space
         set elt_prefix_len 4
      } else {
         set elt_prefix_len 0
      }
      # save room for two spaces after element
      set elt_suffix_len 2

      # compute rows*cols grid size with optimized column number
      # the size of each column is computed to display as much column
      # as possible on each line
      set max_len 0
      foreach arg $args {
         lappend elt_len [set len [expr {[string length $arg] +\
            $elt_suffix_len}]]
         if {$len > $max_len} {
            set max_len $len
         }
      }

      set tty_cols [getTtyColumns]
      # find valid grid by starting with non-optimized solution where each
      # column length is equal to the length of the biggest element to display
      set cur_cols [expr {int($tty_cols / $max_len)}]
      # when display is found too short to display even one column
      if {$cur_cols == 0} {
         set cols 1
         set rows $elt_cnt
         array set col_width [list 0 $max_len]
      } else {
         set cols 0
      }
      set last_round 0
      set restart_loop 0
      while {$cur_cols > $cols} {
         if {!$restart_loop} {
            if {$last_round} {
               incr cur_rows
            } else {
               set cur_rows [expr {int(ceil(double($elt_cnt) / $cur_cols))}]
            }
            for {set i 0} {$i < $cur_cols} {incr i} {
               set cur_col_width($i) 0
            }
            for {set i 0} {$i < $cur_rows} {incr i} {
               set row_width($i) 0
            }
            set istart 0
         } else {
            set istart [expr {$col * $cur_rows}]
            # only remove width of elements from current col
            for {set row 0} {$row < ($i % $cur_rows)} {incr row} {
               incr row_width($row) -[expr {$pre_col_width + $elt_prefix_len}]
            }
         }
         set restart_loop 0
         for {set i $istart} {$i < $elt_cnt} {incr i} {
            set col [expr {int($i / $cur_rows)}]
            set row [expr {$i % $cur_rows}]
            # restart loop if a column width change
            if {[lindex $elt_len $i] > $cur_col_width($col)} {
               set pre_col_width $cur_col_width($col)
               set cur_col_width($col) [lindex $elt_len $i]
               set restart_loop 1
               break
            }
            # end search of maximum number of columns if computed row width
            # is larger than terminal width
            if {[incr row_width($row) +[expr {$cur_col_width($col) \
               + $elt_prefix_len}]] > $tty_cols} {
               # start last optimization pass by increasing row number until
               # reaching number used for previous column number, by doing so
               # this number of column may pass in terminal width, if not
               # fallback to previous number of column
               if {$last_round && $cur_rows == $rows} {
                  incr cur_cols -1
               } else {
                  set last_round 1
               }
               break
            }
         }
         # went through all elements without reaching terminal width limit so
         # this number of column solution is valid, try next with a greater
         # column number
         if {$i == $elt_cnt} {
            set cols $cur_cols
            set rows $cur_rows
            array set col_width [array get cur_col_width]
            # number of column is fixed if last optimization round has started
            # reach end also if there is only one row of results
            if {!$last_round && $rows > 1} {
               incr cur_cols
            }
         }

      }
      reportDebug "displayElementList: list=$args"
      reportDebug "displayElementList: rows/cols=$rows/$cols,\
         lastcol_item_cnt=[expr {int($elt_cnt % $rows)}]"

      for {set row 0} {$row < $rows} {incr row} {
         for {set col 0} {$col < $cols} {incr col} {
            set index [expr {$col * $rows + $row}]
            if {$index < $elt_cnt} {
               if {$display_idx} {
                  append displist [format "%2d) %-$col_width($col)s"\
                     [expr {$index +1}] [lindex $args $index]]
               } else {
                  append displist [format "%-$col_width($col)s"\
                     [lindex $args $index]]
               }
            }
         }
         append displist "\n"
      }
   }
   report "$displist" -nonewline
}

# build list of what to undo then do to move
# from an initial list to a target list
proc getMovementBetweenList {from to} {
   reportDebug "getMovementBetweenList: from($from) to($to)"

   set undo {}
   set do {}

   # determine what element to undo then do
   # to restore a target list from a current list
   # with preservation of the element order
   if {[llength $to] > [llength $from]} {
      set imax [llength $to]
   } else {
      set imax [llength $from]
   }
   set list_equal 1
   for {set i 0} {$i < $imax} {incr i} {
      set to_obj [lindex $to $i]
      set from_obj [lindex $from $i]

      if {$to_obj ne $from_obj} {
         set list_equal 0
      }
      if {$list_equal == 0} {
         if {$to_obj ne ""} {
            lappend do $to_obj
         }
         if {$from_obj ne ""} {
            lappend undo $from_obj
         }
      }
   }

   return [list $undo $do]
}

# build list of currently loaded modules where modulename is registered minus
# module version if loaded version is the default one. a helper list may be
# provided and looked at prior to module search
proc getSimplifiedLoadedModuleList {{helper_raw_list {}}\
   {helper_list {}}} {
   reportDebug "getSimplifiedLoadedModuleList"

   set curr_mod_list {}
   set modpathlist [getModulePathList]
   foreach mod [getLoadedModuleList] {
      # if mod found in a previous LOADEDMODULES list use simplified
      # version of this module found in relative helper list (previously
      # computed simplified list)
      if {[set helper_idx [lsearch -exact $helper_raw_list $mod]] != -1} {
         lappend curr_mod_list [lindex $helper_list $helper_idx]
      # look through modpaths for a simplified mod name if not full path
      } elseif {![isModuleFullPath $mod] && [llength $modpathlist] > 0} {
         set modfile [getModulefileFromLoadedModule $mod]
         set parentmod [file dirname $mod]
         set simplemod $mod
         # simplify to parent name as long as it resolves to current mod
         while {$parentmod ne "."} {
            lassign [getPathToModule $parentmod $modpathlist] parentfile
            if {$parentfile eq $modfile} {
               set simplemod $parentmod
               set parentmod [file dirname $parentmod]
            } else {
               set parentmod "."
            }
         }
         lappend curr_mod_list $simplemod
      } else {
         lappend curr_mod_list $mod
      }
   }

   return $curr_mod_list
}

# get collection target currently set if any.
# a target is a domain on which a collection is only valid.
# when a target is set, only the collections made for that target
# will be available to list and restore, and saving will register
# the target footprint
proc getCollectionTarget {} {
   if {[info exists ::env(MODULES_COLLECTION_TARGET)]} {
      return $::env(MODULES_COLLECTION_TARGET)
   } else {
      return ""
   }
}

# should modulefile version be pinned when saving collection?
proc pinVersionInCollection {} {
   return [expr {[info exists ::env(MODULES_COLLECTION_PIN_VERSION)] &&\
      $::env(MODULES_COLLECTION_PIN_VERSION) eq "1"}]
}

# return saved collections found in user directory which corresponds to
# enabled collection target if any set.
proc findCollections {} {
   if {[info exists ::env(HOME)]} {
      set coll_search "$::env(HOME)/.module/*"
   } else {
      reportErrorAndExit "HOME not defined"
   }

   # find saved collections (matching target suffix)
   set colltarget [getCollectionTarget]
   if {$colltarget ne ""} {
      append coll_search ".$colltarget"
   }

   # workaround 'glob -nocomplain' which does not return permission
   # error on Tcl 8.4, so we need to avoid raising error if no match
   # glob excludes by default files starting with "."
   if {[catch {set coll_list [glob $coll_search]} errMsg ]} {
      if {$errMsg eq "no files matched glob pattern \"$coll_search\""} {
         set coll_list {}
      } else {
         reportErrorAndExit "Cannot access collection directory.\n$errMsg"
      }
   }

   return $coll_list
}

# get filename corresponding to collection name provided as argument.
# name provided may already be a file name. collection description name
# (with target info if any) is returned along with collection filename
proc getCollectionFilename {coll} {
   # initialize description with collection name
   set colldesc $coll

   if {$coll eq ""} {
      reportErrorAndExit "Invalid empty collection name"
   # is collection a filepath
   } elseif {[string first "/" $coll] > -1} {
      # collection target has no influence when
      # collection is specified as a filepath
      set collfile "$coll"
   # elsewhere collection is a name
   } elseif {[info exists ::env(HOME)]} {
      set collfile "$::env(HOME)/.module/$coll"
      # if a target is set, append the suffix corresponding
      # to this target to the collection file name
      set colltarget [getCollectionTarget]
      if {$colltarget ne ""} {
         append collfile ".$colltarget"
         # add knowledge of collection target on description
         append colldesc " (for target \"$colltarget\")"
      }
   } else {
      reportErrorAndExit "HOME not defined"
   }

   return [list $collfile $colldesc]
}

# generate collection content based on provided path and module lists
proc formatCollectionContent {path_list mod_list} {
   set content ""

   # start collection content with modulepaths
   foreach path $path_list {
      # 'module use' prepends paths by default so we clarify
      # path order here with --append flag
      append content "module use --append $path" "\n"
   }

   # then add modules
   foreach mod $mod_list {
      append content "module load $mod" "\n"
   }

   return $content
}

# read given collection file and return the path and module lists it defines
proc readCollectionContent {collfile colldesc} {
   # init lists (maybe coll does not set mod to load)
   set path_list {}
   set mod_list {}

   # read file
   if {[catch {
      set fid [open $collfile r]
      set fdata [split [read $fid] "\n"]
      close $fid
   } errMsg ]} {
      reportErrorAndExit "Collection $colldesc cannot be read.\n$errMsg"
   }

   # analyze collection content
   foreach fline $fdata {
      if {[regexp {module use (.*)$} $fline match patharg] == 1} {
         # paths are appended by default
         set stuff_path "append"
         # manage with "split" multiple paths and path options
         # specified on single line, for instance:
         # module use --append path1 path2 path3
         foreach path [split $patharg] {
            # following path is asked to be appended
            if {($path eq "--append") || ($path eq "-a")\
               || ($path eq "-append")} {
               set stuff_path "append"
            # following path is asked to be prepended
            # collection generated with 'save' does not prepend
            } elseif {($path eq "--prepend") || ($path eq "-p")\
               || ($path eq "-prepend")} {
               set stuff_path "prepend"
            } else {
               # ensure given path is absolute to be able to correctly
               # compare with paths registered in MODULEPATH
               set path [getAbsolutePath $path]
               # add path to end of list
               if {$stuff_path eq "append"} {
                  lappend path_list $path
               # insert path to first position
               } else {
                  set path_list [linsert $path_list 0 $path]
               }
            }
         }
      } elseif {[regexp {module load (.*)$} $fline match modarg] == 1} {
         # manage multiple modules specified on a
         # single line with "split", for instance:
         # module load mod1 mod2 mod3
         set mod_list [concat $mod_list [split $modarg]]
      }
   }

   return [list $path_list $mod_list]
}


########################################################################
# command line commands
#
proc cmdModuleList {} {
   set loadedmodlist [getLoadedModuleList]

   if {[llength $loadedmodlist] == 0} {
      report "No Modulefiles Currently Loaded."
   } else {
      set display_list {}
      foreach mod $loadedmodlist {
         if {$::show_oneperline} {
            lappend display_list $mod
         } else {
            set modfile [getModulefileFromLoadedModule $mod]
            # skip rc find and execution if mod is registered as full path
            if {[isModuleFullPath $mod]} {
               set mtime [getFileMtime $mod]
               set tag_list {}
            # or if loaded module is a virtual module
            } elseif {[isModuleVirtual $mod $modfile]} {
               set mtime [getFileMtime $modfile]
               set tag_list {}
            } else {
               # call getModules to find and execute rc files for this mod
               set dir [getModulepathFromModuleName $modfile $mod]
               array set mod_list [getModules $dir $mod $::show_modtimes]
               # fetch info only if mod found
               if {[info exists mod_list($mod)]} {
                  set mtime [lindex $mod_list($mod) 1]
                  set tag_list [getVersAliasList $mod]
               } else {
                  set tag_list {}
               }
            }

            if {$::show_modtimes} {
               if {[info exists mtime]} {
                  set clock_mtime [clock format $mtime -format\
                     "%Y/%m/%d %H:%M:%S"]
                  unset mtime
               } else {
                  set clock_mtime {}
               }

               # add to display file modification time in addition
               # to potential tags
               lappend display_list [format "%-40s%-20s%19s" $mod\
                  [join $tag_list ":"] $clock_mtime]
            } else {
               if {[llength $tag_list]} {
                  append mod "(" [join $tag_list ":"] ")"
               }
               lappend display_list $mod
            }
         }
      }

      if {$::show_modtimes} {
         displayTableHeader "Package" "Versions" "Last mod."
      }
      report "Currently Loaded Modulefiles:"
      if {$::show_modtimes || $::show_oneperline} {
         set display_idx 0
         set one_per_line 1
      } else {
         set display_idx 1
         set one_per_line 0
      }

      eval displayElementList "noheader" "{}" $one_per_line $display_idx\
         $display_list
   }
}

proc cmdModuleDisplay {args} {
   reportDebug "cmdModuleDisplay: displaying $args"

   pushMode "display"
   set first_report 1
   foreach mod $args {
      lassign [getPathToModule $mod] modfile modname
      if {$modfile ne ""} {
         pushSpecifiedName $mod
         pushModuleName $modname
         # only one separator lines between 2 modules
         if {$first_report} {
            displaySeparatorLine
            set first_report 0
         }
         report "$modfile:\n"
         execute-modulefile $modfile
         popModuleName
         popSpecifiedName
         displaySeparatorLine
      }
   }
   popMode
}

proc cmdModulePaths {mod} {
   reportDebug "cmdModulePaths: ($mod)"

   set dir_list [getModulePathList "exiterronundef"]
   foreach dir $dir_list {
      array unset mod_list
      array set mod_list [getModules $dir $mod 0 "rc_defs_included"]

      # prepare list of dirs for alias/symbol target search, will first search
      # in currently looked dir, then in other dirs following precedence order
      set target_dir_list [concat [list $dir] [replaceFromList $dir_list\
         $dir]]

      # build list of modulefile to print
      foreach elt [array names mod_list] {
         switch -- [lindex $mod_list($elt) 0] {
            {modulefile} {
               lappend ::g_return_text $dir/$elt
            }
            {virtual} {
               lappend ::g_return_text [lindex $mod_list($elt) 2]
            }
            {alias} - {version} {
               # resolve alias target
               set aliastarget [lindex $mod_list($elt) 1]
               lassign [getPathToModule $aliastarget $target_dir_list]\
                  modfile modname
               # add module target as result instead of alias
               if {$modfile ne "" && ![info exists mod_list($modname)]} {
                  lappend ::g_return_text $modfile
               }
            }
         }
      }
   }

   # sort results if any and remove duplicates
   if {[info exists ::g_return_text]} {
      set ::g_return_text [lsort -dictionary -unique $::g_return_text]
   } else {
      # set empty value to return empty if no result
      set ::g_return_text ""
   }
}

proc cmdModulePath {mod} {
   reportDebug "cmdModulePath: ($mod)"
   lassign [getPathToModule $mod] modfile modname
   # if no result set empty value to return empty
   set ::g_return_text $modfile
}

proc cmdModuleWhatIs {{mod {}}} {
   cmdModuleSearch $mod {}
}

proc cmdModuleApropos {{search {}}} {
   cmdModuleSearch {} $search
}

proc cmdModuleSearch {{mod {}} {search {}}} {
   reportDebug "cmdModuleSearch: ($mod, $search)"

   # disable error reporting to avoid modulefile errors
   # to mix with valid search results
   inhibitErrorReport

   lappend searchmod "rc_defs_included"
   if {$mod eq ""} {
      lappend searchmod "wild"
   }
   set foundmod 0
   pushMode "whatis"
   set dir_list [getModulePathList "exiterronundef"]
   foreach dir $dir_list {
      array unset mod_list
      array set mod_list [getModules $dir $mod 0 $searchmod]
      array unset interp_list
      array set interp_list {}

      # build list of modulefile to interpret
      foreach elt [array names mod_list] {
         switch -- [lindex $mod_list($elt) 0] {
            {modulefile} {
               set interp_list($elt) $dir/$elt
               # register module name in a global list (shared across
               # modulepaths) to get hints when solving aliases/version
               set full_list($elt) 1
            }
            {virtual} {
               set interp_list($elt) [lindex $mod_list($elt) 2]
               set full_list($elt) 1
            }
            {alias} - {version} {
               # resolve alias target
               set elt_target [lindex $mod_list($elt) 1]
               if {![info exists full_list($elt_target)]} {
                  lassign [getPathToModule $elt_target $dir]\
                     modfile modname issuetype issuemsg
                  # add module target as result instead of alias
                  if {$modfile ne "" && ![info exists mod_list($modname)]} {
                     set interp_list($modname) $modfile
                     set full_list($modname) 1
                  } elseif {$modfile eq ""} {
                     # if module target not found in current modulepath add to
                     # list for global search after initial modulepath lookup
                     if {[string first "Unable to locate" $issuemsg] == 0} {
                        set extra_search($modname) [list $dir [expr {$elt eq\
                           $mod}]]
                     # register resolution error if alias name matches search
                     } elseif {$elt eq $mod} {
                        set err_list($modname) [list $issuetype $issuemsg]
                     }
                  }
               }
            }
            {invalid} - {accesserr} {
               # register any error occuring on element matching search
               if {$elt eq $mod} {
                  set err_list($elt) $mod_list($elt)
               }
            }
         }
      }

      # in case during modulepath lookup we find an alias target we were
      # looking for in previous modulepath, remove this element from global
      # search list
      foreach elt [array names extra_search] {
         if {[info exists full_list($elt)]} {
            unset extra_search($elt)
         }
      }

      # save results from this modulepath for interpretation step as there
      # is an extra round of search to match missing alias target, we cannot
      # process modulefiles found immediately
      if {[array size interp_list] > 0} {
         set interp_save($dir) [array get interp_list]
      }
   }

   # find target of aliases in all modulepath except the one already tried
   foreach elt [array names extra_search] {
      lassign [getPathToModule $elt "" "no" [lindex $extra_search($elt) 0]]\
         modfile modname issuetype issuemsg issuefile
      # found target so append it to results in corresponding modulepath
      if {$modfile ne ""} {
         # get belonging modulepath dir depending of module kind
         if {[isModuleVirtual $modname $modfile]} {
            set dir [findModulepathFromModulefile\
               $::g_sourceVirtual($modname)]
         } else {
            set dir [getModulepathFromModuleName $modfile $modname]
         }
         array unset interp_list
         if {[info exists interp_save($dir)]} {
            array set interp_list $interp_save($dir)
         }
         set interp_list($modname) $modfile
         set interp_save($dir) [array get interp_list]
      # register resolution error if primal alias name matches search
      } elseif {$modfile eq "" && [lindex $extra_search($elt) 1]} {
         set err_list($modname) [list $issuetype $issuemsg $issuefile]
      }
   }

   # interpret all modulefile we got for each modulepath
   foreach dir $dir_list {
      if {[info exists interp_save($dir)]} {
         array unset interp_list
         array set interp_list $interp_save($dir)
         set foundmod 1
         set display_list {}
         # interpret every modulefiles obtained to get their whatis text
         foreach elt [lsort -dictionary [array names interp_list]] {
            set ::g_whatis {}
            pushSpecifiedName $elt
            pushModuleName $elt
            execute-modulefile $interp_list($elt)
            popModuleName
            popSpecifiedName

            # treat whatis as a multi-line text
            if {$search eq "" || [regexp -nocase $search $::g_whatis]} {
               foreach line $::g_whatis {
                  lappend display_list [format "%20s: %s" $elt $line]
               }
            }
         }

         eval displayElementList $dir "sepline" 1 0 $display_list
      }
   }
   popMode

   reenableErrorReport

   # report errors if a modulefile was searched but not found
   if {$mod ne "" && !$foundmod} {
      # no error registered means nothing was found to match search
      if {![array exists err_list]} {
         set err_list($mod) [list "none" "Unable to locate a modulefile for\
            '$mod'"]
      }
      foreach elt [array names err_list] {
         eval reportIssue $err_list($elt)
      }
   }
}

proc cmdModuleSwitch {old {new {}}} {
   # if a single name is provided it matches for the module to load and in
   # this case the module to unload is searched to find the closest match
   # (loaded module that shares at least the same root name)
   if {$new eq ""} {
      set new $old
      set unload_match "close"
   } else {
      set unload_match "match"
   }

   reportDebug "cmdModuleSwitch: old='$old' new='$new'"

   # attempt load only if unload succeed
   if {![cmdModuleUnload $unload_match $old]} {
      cmdModuleLoad $new
   }
}

proc cmdModuleSave {{coll {default}}} {
   reportDebug "cmdModuleSave: $coll"

   # format collection content, version number of modulefile are saved if
   # version pinning is enabled
   if {[pinVersionInCollection]} {
      set curr_mod_list [getLoadedModuleList]
   } else {
      set curr_mod_list [getSimplifiedLoadedModuleList]
   }
   set save [formatCollectionContent [getModulePathList "returnempty" 0]\
      $curr_mod_list]

   if { [string length $save] == 0} {
      reportErrorAndExit "Nothing to save in a collection"
   }

   # get coresponding filename and its directory
   lassign [getCollectionFilename $coll] collfile colldesc
   set colldir [file dirname $collfile]

   if {![file exists $colldir]} {
      reportDebug "cmdModuleSave: Creating $colldir"
      file mkdir $colldir
   } elseif {![file isdirectory $colldir]} {
      reportErrorAndExit "$colldir exists but is not a directory"
   }

   reportDebug "cmdModuleSave: Saving $collfile"

   if {[catch {
      set fid [open $collfile w]
      puts $fid $save
      close $fid
   } errMsg ]} {
      reportErrorAndExit "Collection $colldesc cannot be saved.\n$errMsg"
   }
}

proc cmdModuleRestore {{coll {default}}} {
   reportDebug "cmdModuleRestore: $coll"

   # get coresponding filename
   lassign [getCollectionFilename $coll] collfile colldesc

   if {![file exists $collfile]} {
      reportErrorAndExit "Collection $colldesc cannot be found"
   }

   # read collection
   lassign [readCollectionContent $collfile $colldesc] coll_path_list\
      coll_mod_list

   # collection should at least define a path or a mod
   if {[llength $coll_path_list] == 0 && [llength $coll_mod_list] == 0} {
      reportErrorAndExit "$colldesc is not a valid collection"
   }

   # fetch what is currently loaded
   set curr_path_list [getModulePathList "returnempty" 0]
   # get current loaded module list in simplified and raw versions
   # these lists may be used later on, see below
   set curr_mod_list_raw [getLoadedModuleList]
   set curr_mod_list [getSimplifiedLoadedModuleList]

   # determine what module to unload to restore collection
   # from current situation with preservation of the load order
   lassign [getMovementBetweenList $curr_mod_list $coll_mod_list] \
      mod_to_unload mod_to_load
   # determine unload movement with raw loaded list in case versions are
   # pinning in saved collection
   lassign [getMovementBetweenList $curr_mod_list_raw $coll_mod_list] \
      mod_to_unload_raw mod_to_load_raw
   if {[llength $mod_to_unload] > [llength $mod_to_unload_raw]} {
      set mod_to_unload $mod_to_unload_raw
   }

   # proceed as well for modulepath
   lassign [getMovementBetweenList $curr_path_list $coll_path_list] \
      path_to_unuse path_to_use

   # unload modules
   if {[llength $mod_to_unload] > 0} {
      eval cmdModuleUnload "match" [lreverse $mod_to_unload]
   }
   # unuse paths
   if {[llength $path_to_unuse] > 0} {
      eval cmdModuleUnuse [lreverse $path_to_unuse]
   }

   # since unloading a module may unload other modules or
   # paths, what to load/use has to be determined after
   # the undo phase, so current situation is fetched again
   set curr_path_list [getModulePathList "returnempty" 0]

   # here we may be in a situation were no more path is left
   # in module path, so we cannot easily compute the simplified loaded
   # module list. so we provide two helper lists: simplified and raw
   # versions of the loaded module list computed before starting to
   # unload modules. these helper lists may help to learn the
   # simplified counterpart of a loaded module if it was already loaded
   # before starting to unload modules
   set curr_mod_list [getSimplifiedLoadedModuleList\
      $curr_mod_list_raw $curr_mod_list]
   set curr_mod_list_raw [getLoadedModuleList]

   # determine what module to load to restore collection
   # from current situation with preservation of the load order
   lassign [getMovementBetweenList $curr_mod_list $coll_mod_list] \
      mod_to_unload mod_to_load
   # determine load movement with raw loaded list in case versions are
   # pinning in saved collection
   lassign [getMovementBetweenList $curr_mod_list_raw $coll_mod_list] \
      mod_to_unload_raw mod_to_load_raw
   if {[llength $mod_to_load] > [llength $mod_to_load_raw]} {
      set mod_to_load $mod_to_load_raw
   }

   # proceed as well for modulepath
   lassign [getMovementBetweenList $curr_path_list $coll_path_list] \
      path_to_unuse path_to_use

   # use paths
   if {[llength $path_to_use] > 0} {
      # always append path here to guaranty the order
      # computed above in the movement lists
      eval cmdModuleUse --append $path_to_use
   }

   # load modules
   if {[llength $mod_to_load] > 0} {
      eval cmdModuleLoad $mod_to_load
   }
}

proc cmdModuleSaverm {{coll {default}}} {
   reportDebug "cmdModuleSaverm: $coll"

   # avoid to remove any kind of file with this command
   if {[string first "/" $coll] > -1} {
      reportErrorAndExit "Command does not remove collection specified as\
         filepath"
   }

   # get coresponding filename
   lassign [getCollectionFilename $coll] collfile colldesc

   if {![file exists $collfile]} {
      reportErrorAndExit "Collection $colldesc cannot be found"
   }

   # attempt to delete specified colletion
   if {[catch {
      file delete $collfile
   } errMsg ]} {
      reportErrorAndExit "Collection $colldesc cannot be removed.\n$errMsg"
   }
}

proc cmdModuleSaveshow {{coll {default}}} {
   reportDebug "cmdModuleSaveshow: $coll"

   # get coresponding filename
   lassign [getCollectionFilename $coll] collfile colldesc

   if {![file exists $collfile]} {
      reportErrorAndExit "Collection $colldesc cannot be found"
   }

   # read collection
   lassign [readCollectionContent $collfile $colldesc] coll_path_list\
      coll_mod_list

   # collection should at least define a path or a mod
   if {[llength $coll_path_list] == 0 && [llength $coll_mod_list] == 0} {
      reportErrorAndExit "$colldesc is not a valid collection"
   }

   displaySeparatorLine
   report "$collfile:\n"
   report [formatCollectionContent $coll_path_list $coll_mod_list]
   displaySeparatorLine
}

proc cmdModuleSavelist {} {
   # if a target is set, only list collection matching this
   # target (means having target as suffix in their name)
   set colltarget [getCollectionTarget]
   if {$colltarget ne ""} {
      set suffix ".$colltarget"
      set targetdesc " (for target \"$colltarget\")"
   } else {
      set suffix ""
      set targetdesc ""
   }

   reportDebug "cmdModuleSavelist: list collections for target\
      \"$colltarget\""

   set coll_list [findCollections]

   if { [llength $coll_list] == 0} {
      report "No named collection$targetdesc."
   } else {
      set list {}
      if {$::show_modtimes} {
         displayTableHeader "Collection" "Last mod."
      }
      report "Named collection list$targetdesc:"
      set display_list {}
      if {$::show_modtimes || $::show_oneperline} {
         set display_idx 0
         set one_per_line 1
      } else {
         set display_idx 1
         set one_per_line 0
      }

      foreach coll [lsort -dictionary $coll_list] {
         # remove target suffix from names to display
         regsub "$suffix$" [file tail $coll] {} mod

         # no need to test mod consistency as findCollections does not return
         # collection whose name starts with "."
         if {$::show_modtimes} {
            set filetime [clock format [getFileMtime $coll]\
               -format "%Y/%m/%d %H:%M:%S"]
            lappend display_list [format "%-60s%19s" $mod $filetime]
         } else {
            lappend display_list $mod
         }
      }

      eval displayElementList "noheader" "{}" $one_per_line $display_idx\
         $display_list
   }
}


proc cmdModuleSource {args} {
   reportDebug "cmdModuleSource: $args"
   foreach fpath $args {
      set absfpath [getAbsolutePath $fpath]
      if {$fpath eq ""} {
         reportErrorAndExit "File name empty"
      } elseif {[file exists $absfpath]} {
         pushMode "load"
         pushSpecifiedName $absfpath
         pushModuleName $absfpath
         # relax constraint of having a magic cookie at the start of the
         # modulefile to execute as sourced files may need more flexibility
         # as they may be managed outside of the modulefile environment like
         # the initialization modulerc file
         execute-modulefile $absfpath 0
         popModuleName
         popSpecifiedName
         popMode
      } else {
         reportErrorAndExit "File $fpath does not exist"
      }
   }
}

proc cmdModuleUnsource {args} {
   reportDebug "cmdModuleUnsource: $args"
   foreach fpath $args {
      set absfpath [getAbsolutePath $fpath]
      if {$fpath eq ""} {
         reportErrorAndExit "File name empty"
      } elseif {[file exists $absfpath]} {
         pushMode "unload"
         pushSpecifiedName $absfpath
         pushModuleName $absfpath
         # relax constraint of having a magic cookie at the start of the
         # modulefile to execute as sourced files may need more flexibility
         # as they may be managed outside of the modulefile environment like
         # the initialization modulerc file
         execute-modulefile $absfpath 0
         popModuleName
         popSpecifiedName
         popMode
      } else {
         reportErrorAndExit "File $fpath does not exist"
      }
   }
}

proc cmdModuleLoad {args} {
   reportDebug "cmdModuleLoad: loading $args"

   set ret 0
   pushMode "load"
   foreach mod $args {
      lassign [getPathToModule $mod] modfile modname
      if {$modfile ne ""} {
         # check if passed modname correspond to an already loaded modfile
         # and get its loaded name (in case it has been loaded as full path)
         set loadedmodname [getLoadedMatchingName $modname]
         if {$loadedmodname ne ""} {
            set modname $loadedmodname
         }

         set currentModule $modname

         if {$::g_force || ![isModuleLoaded $currentModule]} {
            pushSpecifiedName $mod
            pushModuleName $currentModule
            pushSettings

            if {[execute-modulefile $modfile]} {
               restoreSettings
               set ret 1
            } else {
               add-path "append" LOADEDMODULES $currentModule
               # allow duplicate modfile entries for virtual modules
               add-path "append" --duplicates _LMFILES_ $modfile
               # update cache arrays
               setLoadedModule $currentModule $modfile
            }

            popSettings
            popModuleName
            popSpecifiedName
         } else {
            reportDebug "cmdModuleLoad: $modname ($modfile) already loaded"
         }
      } else {
         set ret 1
      }
   }
   popMode

   return $ret
}

proc cmdModuleUnload {match args} {
   reportDebug "cmdModuleUnload: unloading $args (match=$match)"

   set ret 0
   pushMode "unload"
   foreach mod $args {
      # resolve by also looking at matching loaded module
      lassign [getPathToModule $mod {} $match] modfile modname
      if {$modfile ne ""} {
         set currentModule $modname

         if {[isModuleLoaded $currentModule]} {
            pushSpecifiedName $mod
            pushModuleName $currentModule
            pushSettings

            if {[execute-modulefile $modfile]} {
               restoreSettings
               set ret 1
            } else {
               # get module position in loaded list to remove corresponding
               # loaded modulefile (entry at same position in _LMFILES_)
               # need the unfiltered loaded module list to get correct index
               set lmidx [lsearch -exact [getLoadedModuleList 0]\
                  $currentModule]
               unload-path LOADEDMODULES $currentModule
               unload-path --index _LMFILES_ $lmidx
               # update cache arrays
               unsetLoadedModule $currentModule $modfile
            }

            popSettings
            popModuleName
            popSpecifiedName
         } else {
            reportDebug "cmdModuleUnload: $modname ($modfile) is not loaded"
         }
      } else {
         set ret 1
      }
   }
   popMode

   return $ret
}

proc cmdModulePurge {} {
   reportDebug "cmdModulePurge"

   eval cmdModuleUnload "match" [lreverse [getLoadedModuleList]]
}

proc cmdModuleReload {} {
   reportDebug "cmdModuleReload"

   set list [getLoadedModuleList]
   set rlist [lreverse $list]
   foreach mod $rlist {
      cmdModuleUnload "match" $mod
   }
   foreach mod $list {
      cmdModuleLoad $mod
   }
}

proc cmdModuleAliases {} {
   # disable error reporting to avoid modulefile errors
   # to mix with avail results
   inhibitErrorReport

   # parse paths to fill g_moduleAlias and g_moduleVersion
   foreach dir [getModulePathList "exiterronundef"] {
      getModules $dir "" 0 ""
   }

   reenableErrorReport

   set display_list {}
   foreach name [lsort -dictionary [array names ::g_moduleAlias]] {
      lappend display_list "$name -> $::g_moduleAlias($name)"
   }
   eval displayElementList "Aliases" "sepline" 1 0 $display_list

   set display_list {}
   foreach name [lsort -dictionary [array names ::g_moduleVersion]] {
      lappend display_list "$name -> $::g_moduleVersion($name)"
   }
   eval displayElementList "Versions" "sepline" 1 0 $display_list
}

proc cmdModuleAvail {{mod {*}}} {
   if {$::show_modtimes || $::show_oneperline} {
      set one_per_line 1
      set hstyle "terse"
      set theader_shown 0
      set theader_cols [list "Package/Alias" "Versions" "Last mod."]
   } else {
      set one_per_line 0
      set hstyle "sepline"
   }

   # disable error reporting to avoid modulefile errors
   # to mix with avail results
   inhibitErrorReport


   # look if aliases have been defined in the global or user-specific
   # modulerc and display them if any in a dedicated list
   set display_list [listModules "" "$mod" 1 $::show_filter "rc_alias_only"]
   if {[llength $display_list] > 0 && $::show_modtimes && !$theader_shown} {
      set theader_shown 1
      eval displayTableHeader $theader_cols
   }
   eval displayElementList "{global/user modulerc}" $hstyle $one_per_line 0\
      $display_list

   foreach dir [getModulePathList "exiterronundef"] {
      set display_list [listModules $dir "$mod" 1 $::show_filter]
      if {[llength $display_list] > 0 && $::show_modtimes && !$theader_shown} {
         set theader_shown 1
         eval displayTableHeader $theader_cols
      }
      eval displayElementList $dir $hstyle $one_per_line 0 $display_list
   }

   reenableErrorReport
}

proc cmdModuleUse {args} {
   reportDebug "cmdModuleUse: $args"

   if {$args eq ""} {
      showModulePath
   } else {
      set pos "prepend"
      foreach path $args {
         switch -- $path {
            {-a} - {--append} - {-append} {
               set pos "append"
            }
            {-p} - {--prepend} - {-prepend} {
               set pos "prepend"
            }
            {} {
               reportError "Directory name empty"
            }
            default {
               # tranform given path in an absolute path to avoid
               # dependency to the current work directory.
               set path [getAbsolutePath $path]
               if {[file isdirectory [resolvStringWithEnv $path]]} {
                  pushMode "load"
                  catch {
                     add-path $pos MODULEPATH $path
                  }
                  popMode
               } else {
                  reportError "Directory '$path' not found"
               }
            }
         }
      }
   }
}

proc cmdModuleUnuse {args} {
   reportDebug "cmdModuleUnuse: $args"

   if {$args eq ""} {
      showModulePath
   } else {
      foreach path $args {
         # get current module path list
         # no absolute path conversion for the moment
         if {![info exists modpathlist]} {
            set modpathlist [getModulePathList "returnempty" 0 0]
         }

         # skip empty string
         if {$path eq ""} {
            reportError "Directory name empty"
            continue
         }

         # transform given path in an absolute path which should have been
         # registered in the MODULEPATH env var. however for compatibility
         # with previous behavior where relative paths were registered in
         # MODULEPATH given path is first checked against current path list
         set abspath [getAbsolutePath $path]
         if {[lsearch -exact $modpathlist $path] >= 0} {
            set unusepath $path
         } elseif {[lsearch -exact $modpathlist $abspath] >= 0} {
            set unusepath $abspath
         } else {
            set unusepath ""
         }

         if {$unusepath ne ""} {
            pushMode "unload"
            catch {
               unload-path MODULEPATH $unusepath
            }
            popMode

            # refresh path list after unload
            set modpathlist [getModulePathList "returnempty" 0 0]
            if {[lsearch -exact $modpathlist $unusepath] >= 0} {
               reportWarning "Did not unuse $unusepath"
            }
         }
      }
   }
}

proc cmdModuleAutoinit {} {
   reportDebug "cmdModuleAutoinit:"

   # flag to make renderSettings define the module command
   set ::g_autoInit 1

   # initialize env variables around module command
   pushMode "load"

   # default MODULESHOME
   setenv MODULESHOME "/usr/share/Modules"

   # register command location
   setenv MODULES_CMD [getAbsolutePath $::argv0]

   # define current Modules version if versioning enabled
   #if {![info exists ::env(MODULE_VERSION)]} {
   #   setenv MODULE_VERSION "4.1.4"
   #   setenv MODULE_VERSION_STACK "4.1.4"
   #}

   # initialize default MODULEPATH and LOADEDMODULES
   if {![info exists ::env(MODULEPATH)] || $::env(MODULEPATH) eq ""} {
      # set modpaths defined in .modulespath config file if it exists
      if {[file readable "/usr/share/Modules/init/.modulespath"]} {
         set fid [open "/usr/share/Modules/init/.modulespath" r]
         set fdata [split [read $fid] "\n"]
         close $fid
         foreach fline $fdata {
            if {[regexp {^\s*(.*?)\s*(#.*|)$} $fline match patharg] == 1\
               && $patharg ne ""} {
               eval cmdModuleUse --append [split $patharg ":"]
            }
         }
      }

      if {![info exists ::env(MODULEPATH)]} {
         setenv MODULEPATH ""
      }
   }
   if {![info exists ::env(LOADEDMODULES)]} {
      setenv LOADEDMODULES ""
   }

   # source initialization modulerc if any and if no env already initialized
   if {$::env(MODULEPATH) eq "" && $::env(LOADEDMODULES) eq ""\
      && [file exists "/usr/share/Modules/init/modulerc"]} {
      cmdModuleSource "/usr/share/Modules/init/modulerc"
   }

   popMode
}

proc cmdModuleInit {args} {
   set init_cmd [lindex $args 0]
   set init_list [lrange $args 1 end]
   set notdone 1
   set nomatch 1

   reportDebug "cmdModuleInit: $args"

   # Define startup files for each shell
   set files(csh) [list ".modules" ".cshrc" ".cshrc_variables" ".login"]
   set files(tcsh) [list ".modules" ".tcshrc" ".cshrc" ".cshrc_variables"\
      ".login"]
   set files(sh) [list ".modules" ".bash_profile" ".bash_login" ".profile"\
      ".bashrc"]
   set files(bash) $files(sh)
   set files(ksh) $files(sh)
   set files(fish) [list ".modules" ".config/fish/config.fish"]
   set files(zsh) [list ".modules" ".zshrc" ".zshenv" ".zlogin"]

   # Process startup files for this shell
   set current_files $files($::g_shell)
   foreach filename $current_files {
      if {$notdone} {
         set filepath $::env(HOME)
         append filepath "/" $filename

         reportDebug "cmdModuleInit: Looking at $filepath"
         if {[file readable $filepath] && [file isfile $filepath]} {
            set newinit {}
            set thismatch 0
            set fid [open $filepath r]

            while {[gets $fid curline] >= 0} {
               # Find module load/add command in startup file 
               set comments {}
               if {$notdone && [regexp {^([ \t]*module[ \t]+(load|add)[\
                  \t]*)(.*)} $curline match cmd subcmd modules]} {
                  set nomatch 0
                  set thismatch 1
                  regexp {([ \t]*\#.+)} $modules match comments
                  regsub {\#.+} $modules {} modules

                  # remove existing references to the named module from
                  # the list Change the module command line to reflect the 
                  # given command
                  switch -- $init_cmd {
                     {list} {
                        if {![info exists notheader]} {
                           report "$::g_shell initialization file\
                              \$HOME/$filename loads modules:"
                           set notheader 0
                        }
                        report "\t$modules"
                     }
                     {add} {
                        foreach newmodule $init_list {
                           set modules [replaceFromList $modules $newmodule]
                        }
                        lappend newinit "$cmd$modules $init_list$comments"
                        # delete new modules in potential next lines
                        set init_cmd "rm"
                     }
                     {prepend} {
                        foreach newmodule $init_list {
                           set modules [replaceFromList $modules $newmodule]
                        }
                        lappend newinit "$cmd$init_list $modules$comments"
                        # delete new modules in potential next lines
                        set init_cmd "rm"
                     }
                     {rm} {
                        set oldmodcount [llength $modules]
                        foreach oldmodule $init_list {
                           set modules [replaceFromList $modules $oldmodule]
                        }
                        set modcount [llength $modules]
                        if {$modcount > 0} {
                           lappend newinit "$cmd$modules$comments"
                        } else {
                           lappend newinit [string trim $cmd]
                        }
                        if {$oldmodcount > $modcount} {
                           set notdone 0
                        }
                     }
                     {switch} {
                        set oldmodule [lindex $init_list 0]
                        set newmodule [lindex $init_list 1]
                        set newmodules [replaceFromList $modules\
                           $oldmodule $newmodule]
                        lappend newinit "$cmd$newmodules$comments"
                        if {"$modules" ne "$newmodules"} {
                           set notdone 0
                        }
                     }
                     {clear} {
                        lappend newinit [string trim $cmd]
                     }
                  }
               } else {
                  # copy the line from the old file to the new
                  lappend newinit $curline
               }
            }

            close $fid

            if {$init_cmd ne "list" && $thismatch} {
               reportDebug "cmdModuleInit: Writing $filepath"
               if {[catch {
                  set fid [open $filepath w]
                  puts $fid [join $newinit "\n"]
                  close $fid
               } errMsg ]} {
                  reportErrorAndExit "Init file $filepath cannot be\
                     written.\n$errMsg"
               }
            }
         }
      }
   }

   # quit in error if command was not performed due to no match
   if {$nomatch && $init_cmd ne "list"} {
      reportErrorAndExit "Cannot find a 'module load' command in any of the\
         '$::g_shell' startup files"
   }
}

# provide access to modulefile specific commands from the command-line, making
# them standing as a module sub-command (see module procedure)
proc cmdModuleResurface {cmd args} {
   reportDebug "cmdModuleResurface: cmd='$cmd', args='$args'"

   pushMode "load"
   pushCommandName $cmd

   # run modulefile command and get its result
   if {[catch {eval $cmd $args} res]} {
      # report error if any and return false
      reportError $res
   } else {
      # register result depending of return kind (false or text)
      switch -- $cmd {
         {module-info} {
            set ::g_return_text $res
         }
         default {
            if {$res == 0} {
               # render false if command returned false
               set ::g_return_false 1
            }
         }
      }
   }

   popCommandName
   popMode
}

proc cmdModuleTest {args} {
   reportDebug "cmdModuleTest: testing $args"

   pushMode "test"
   set first_report 1
   foreach mod $args {
      lassign [getPathToModule $mod] modfile modname
      if {$modfile ne ""} {
         pushSpecifiedName $mod
         pushModuleName $modname
         # only one separator lines between 2 modules
         if {$first_report} {
            displaySeparatorLine
            set first_report 0
         }
         report "Module Specific Test for $modfile:\n"
         execute-modulefile $modfile
         popModuleName
         popSpecifiedName
         displaySeparatorLine
      }
   }
   popMode
}

proc cmdModuleHelp {args} {
   pushMode "help"
   set first_report 1
   foreach arg $args {
      lassign [getPathToModule $arg] modfile modname

      if {$modfile ne ""} {
         pushSpecifiedName $arg
         pushModuleName $modname
         # only one separator lines between 2 modules
         if {$first_report} {
            displaySeparatorLine
            set first_report 0
         }
         report "Module Specific Help for $modfile:\n"
         execute-modulefile $modfile
         popModuleName
         popSpecifiedName
         displaySeparatorLine
      }
   }
   popMode
   if {[llength $args] == 0} {
      reportVersion
      report {Usage: module [options] [command] [args ...]

Loading / Unloading commands:
  add | load      modulefile [...]  Load modulefile(s)
  rm | unload     modulefile [...]  Remove modulefile(s)
  purge                             Unload all loaded modulefiles
  reload | refresh                  Unload then load all loaded modulefiles
  switch | swap   [mod1] mod2       Unload mod1 and load mod2

Listing / Searching commands:
  list            [-t|-l]           List loaded modules
  avail   [-d|-L] [-t|-l] [mod ...] List all or matching available modules
  aliases                           List all module aliases
  whatis          [modulefile ...]  Print whatis information of modulefile(s)
  apropos | keyword | search  str   Search all name and whatis containing str
  is-loaded       [modulefile ...]  Test if any of the modulefile(s) are loaded
  is-avail        modulefile [...]  Is any of the modulefile(s) available
  info-loaded     modulefile        Get full name of matching loaded module(s)

Collection of modules handling commands:
  save            [collection|file] Save current module list to collection
  restore         [collection|file] Restore module list from collection or file
  saverm          [collection]      Remove saved collection
  saveshow        [collection|file] Display information about collection
  savelist        [-t|-l]           List all saved collections
  is-saved        [collection ...]  Test if any of the collection(s) exists

Shell's initialization files handling commands:
  initlist                          List all modules loaded from init file
  initadd         modulefile [...]  Add modulefile to shell init file
  initrm          modulefile [...]  Remove modulefile from shell init file
  initprepend     modulefile [...]  Add to beginning of list in init file
  initswitch      mod1 mod2         Switch mod1 with mod2 from init file
  initclear                         Clear all modulefiles from init file

Environment direct handling commands:
  prepend-path [-d c] var val [...] Prepend value to environment variable
  append-path [-d c] var val [...]  Append value to environment variable
  remove-path [-d c] var val [...]  Remove value from environment variable

Other commands:
  help            [modulefile ...]  Print this or modulefile(s) help info
  display | show  modulefile [...]  Display information about modulefile(s)
  test            [modulefile ...]  Test modulefile(s)
  use     [-a|-p] dir [...]         Add dir(s) to MODULEPATH variable
  unuse           dir [...]         Remove dir(s) from MODULEPATH variable
  is-used         [dir ...]         Is any of the dir(s) enabled in MODULEPATH
  path            modulefile        Print modulefile path
  paths           modulefile        Print path of matching available modules
  source          scriptfile [...]  Execute scriptfile(s)

Switches:
  -t | --terse    Display output in terse format
  -l | --long     Display output in long format
  -d | --default  Only show default versions available
  -L | --latest   Only show latest versions available
  -a | --append   Append directory to MODULEPATH
  -p | --prepend  Prepend directory to MODULEPATH

Options:
  -h | --help     This usage info
  -V | --version  Module version
  -D | --debug    Enable debug messages
  --paginate      Pipe mesg output into a pager if stream attached to terminal
  --no-pager      Do not pipe message output into a pager}
   }
}

########################################################################
# main program

# needed on a gentoo system. Shouldn't hurt since it is
# supposed to be the default behavior
fconfigure stderr -translation auto

if {[catch {
   # parse all command-line arguments before doing any action, no output is
   # made during argument parse to wait for potential paging to be setup
   set show_help 0
   set show_version 0
   reportDebug "CALLING $argv0 $argv"

   # source site configuration script if any
   if {[file readable $g_siteconfig]} {
      reportDebug "Source site configuration ($g_siteconfig)"
      if {[catch {source $g_siteconfig} errMsg]} {
         reportErrorAndExit "Site configuration source failed\n$errMsg"
      }
   }

   # Parse shell
   set g_shell [lindex $argv 0]
   switch -- $g_shell {
      {sh} - {bash} - {ksh} - {zsh} {
         set g_shellType sh
      }
      {csh} - {tcsh} {
         set g_shellType csh
      }
      {fish} - {cmd} - {tcl} - {perl} - {python} - {ruby} - {lisp} - {cmake}\
         - {r} {
         set g_shellType $g_shell
      }
      default {
         reportErrorAndExit "Unknown shell type \'($g_shell)\'"
      }
   }

   # extract options and command switches from other args
   set otherargv {}
   set ddelimarg 0
   foreach arg [lrange $argv 1 end] {
      if {[info exists ignore_next_arg]} {
         unset ignore_next_arg
      } else {
         switch -glob -- $arg {
            {-D} - {--debug} {
               set g_debug 1
            }
            {--help} - {-h} {
               set show_help 1
            }
            {-V} - {--version} {
               set show_version 1
            }
            {--paginate} {
               set asked_pager 1
            }
            {--no-pager} {
               set asked_pager 0
            }
            {-t} - {--terse} {
               set show_oneperline 1
               set show_modtimes 0
            }
            {-l} - {--long} {
               set show_modtimes 1
               set show_oneperline 0
            }
            {-d} - {--default} {
               # in case of *-path command, -d means --delim
               if {$arg eq "-d" && $ddelimarg} {
                  lappend otherargv $arg
               } else {
                  set show_filter "onlydefaults"
               }
            }
            {-L} - {--latest} {
               set show_filter "onlylatest"
            }
            {-a} - {--append} - {-append} - {-p} - {--prepend} - {-prepend} \
            - {--delim} - {-delim} - {--delim=*} - {-delim=*} \
            - {--duplicates} - {--index} {
               # command-specific switches interpreted later on
               lappend otherargv $arg
            }
            {append-path} - {prepend-path} - {remove-path} {
               # detect *-path commands to say -d means --delim, not --default
               set ddelimarg 1
               lappend otherargv $arg
            }
            {-f} - {--force} - {--human} - {-v} - {--verbose} - {-s} -\
               {--silent} - {-c} - {--create} - {-i} - {--icase} -\
               {--userlvl=*} {
               # ignore C-version specific option, no error only warning
               reportWarning "Unsupported option '$arg'"
            }
            {-u} - {--userlvl} {
               reportWarning "Unsupported option '$arg'"
               # also ignore argument value
               set ignore_next_arg 1
            }
            {-*} {
                reportErrorAndExit "Invalid option '$arg'\nTry\
                  'module --help' for more information."
            }
            default {
               lappend otherargv $arg
            }
         }
      }
   }

   # now options are known initialize error report (start pager if enabled)
   initErrorReport

   # put back quarantine variables in env, if quarantine mechanism supported
   if {[info exists env(MODULES_RUN_QUARANTINE)] && $g_shellType ne "csh"} {
      foreach var [split $env(MODULES_RUN_QUARANTINE) " "] {
         # check variable name is valid
         if {[regexp {^[A-Za-z_][A-Za-z0-9_]*$} $var]} {
            set quarvar "${var}_modquar"
            # put back value
            if {[info exists env($quarvar)]} {
               reportDebug "Release '$var' environment variable from\
                  quarantine ($env($quarvar))"
               set env($var) $env($quarvar)
               unset env($quarvar)
            # or unset env var if no value found in quarantine
            } elseif {[info exists env($var)]} {
               reportDebug "Unset '$var' environment variable after\
                  quarantine"
               unset env($var)
            }
         } elseif {[string length $var] > 0} {
            reportWarning "Bad variable name set in MODULES_RUN_QUARANTINE\
               ($var)"
         }
      }
   }

   if {$show_help} {
      cmdModuleHelp
      cleanupAndExit 0
   }
   if {$show_version} {
      reportVersion
      cleanupAndExit 0
   }

   set command [lindex $otherargv 0]
   # default command is help if none supplied
   if {$command eq ""} {
      set command "help"
      # clear other args if no command name supplied
      set otherargv {}
   } else {
      set otherargv [lreplace $otherargv 0 0]
   }

   # no modulefile is currently being interpreted
   pushModuleFile {}

   # Find and execute any .modulerc file found in the module directories
   # defined in env(MODULESPATH)
   runModulerc

   # eval needed to pass otherargv as list to module proc
   eval module $command $otherargv
} errMsg ]} {
   # no use of reportError here to get independent from any
   # previous error report inhibition
   report "ERROR: $errMsg"
   cleanupAndExit 1
}

cleanupAndExit 0

# ;;; Local Variables: ***
# ;;; mode:tcl ***
# ;;; End: ***
# vim:set tabstop=3 shiftwidth=3 expandtab autoindent:
