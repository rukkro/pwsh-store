tclsh
puts [open "flash:reset.tcl" w+] {
puts "Backing up startup-config"
typeahead ""
puts [exec "copy nvram:startup-config flash:base.cfg" ]
puts "Erasing Configuration"
typeahead ""
puts [ exec "write erase" ]
puts "Erasing VLAN Database"
typeahead ""
puts [ exec "del flash:vlan.dat" ]
puts "Copying Base Configuration To Startup"
typeahead ""
puts [ exec "copy flash:base.cfg nvram:startup-config" ]
typeahead ""
puts [ exec "copy nvram:startup-config nvram:running-config" ]
typeahead ""
puts "Reloading device to generate new VLAN Database"
typeahead ""
puts [ exec "reload" ]
typeahead ""
}