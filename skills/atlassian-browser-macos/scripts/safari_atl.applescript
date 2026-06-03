-- safari_atl.applescript
-- Injects base64-encoded JS into the first Safari tab whose URL matches a host
-- filter, then polls for the async result. Returns the result JSON on stdout.
--
-- usage: osascript safari_atl.applescript <hostFilter> <base64js> <timeoutMs>
--
-- Requires: Safari > Develop > "Allow JavaScript from Apple Events" (one-time).

on run argv
	if (count of argv) < 3 then return "{\"status\":0,\"ok\":false,\"error\":\"usage: hostFilter b64 timeoutMs\"}"
	set hostFilter to item 1 of argv
	set b64 to item 2 of argv
	set timeoutMs to (item 3 of argv) as integer

	tell application "Safari"
		if not running then return "{\"status\":0,\"ok\":false,\"error\":\"Safari is not running\"}"
		set targetTab to missing value
		repeat with w in windows
			repeat with t in tabs of w
				try
					set u to URL of t
				on error
					set u to ""
				end try
				if u is not missing value and u contains hostFilter then
					set targetTab to t
					exit repeat
				end if
			end repeat
			if targetTab is not missing value then exit repeat
		end repeat
		if targetTab is missing value then return "{\"status\":0,\"ok\":false,\"error\":\"no tab whose URL contains '" & hostFilter & "' — open the Atlassian site first\"}"

		try
			-- NOTE: eval(atob(...)) runs OUR OWN script (built by atl_safari.sh and
			-- base64-encoded only to avoid AppleScript string-escaping of JS). It is
			-- not untrusted input; base64 keeps the payload free of quotes/newlines
			-- that would otherwise break the AppleScript string literal.
			do JavaScript "eval(atob('" & b64 & "'))" in targetTab
		on error errMsg
			return "{\"status\":0,\"ok\":false,\"error\":\"inject failed: " & errMsg & " (enable Develop > Allow JavaScript from Apple Events)\"}"
		end try

		set waited to 0
		repeat
			set r to do JavaScript "(window.__ATL_DONE)?JSON.stringify(window.__ATL_RESULT):''" in targetTab
			if r is not "" and r is not missing value then return r
			delay 0.2
			set waited to waited + 200
			if waited > timeoutMs then return "{\"status\":0,\"ok\":false,\"error\":\"timeout after " & timeoutMs & "ms\"}"
		end repeat
	end tell
end run
