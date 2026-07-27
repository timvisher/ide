on currentCalendar()
	set calendarName to "Fantastical"
	try
		set calendarName to paragraph 1 of (read POSIX file ((POSIX path of (path to home folder)) & ".config/timvisher/ide/AppleScript/Script Libraries/timvisher Calendar.config/default_calendar"))
	end try
	return calendarName
end currentCalendar

on coldStart()
	tell application (my currentCalendar()) to activate
end coldStart
