#!/usr/bin/env python3

'''This is a Burp Suite extension I wrote to give the ability of sleeping (waiting) for a certain amount of time between certain requests that are made while not sleeping in between other requests.  
This solves a specific problem Burp Suite has when performing a scan of 'crawl and audit' on sites that use mfa for login but the site only allows the mfa code number to be used once.  Once the mfa code number is used, the site does not allow using that same code number again.  This causes Burp Suite scans of 'crawl and audit' to error on login requests since Burp Suite issues many login requests within 30 seconds.
The mfa code number gets renewed to a different number every 30 seconds.  So this extension adds functionality to Burp Suite that allows sleeping 30 seconds after each mfa code number that is submitted while not sleeping for other requests.  
The amount of time can easilly be changed by changing the time.sleep amount to a different amount.  
This extension is helpful not only for solving this Burp Suite issue, but any type of requests that require a sleep before issuing the next request, while not sleeping for all other requests. This can be configured to suit other requests by changing the string 'MFA_CODE' (which triggers the sleep action) to a different string that is expected in the response.
'''

from burp import IBurpExtender, IExtensionStateListener, IHttpListener, IHttpRequestResponse, ISessionHandlingAction
import time

class BurpExtender(IBurpExtender, IExtensionStateListener, IHttpListener, ISessionHandlingAction):
    def registerExtenderCallbacks(self, callbacks):
        self._callbacks = callbacks
        self._helpers = callbacks.getHelpers()
        self._callbacks.setExtensionName("Request Delay Extension")
        self._callbacks.registerHttpListener(self)
        self._callbacks.registerSessionHandlingAction(self)
        
        # Add action to session handling rules
        self._callbacks.addSessionHandlingAction(self)

    def processHttpMessage(self, toolFlag, messageIsRequest, messageInfo):
        if messageIsRequest:
            request = messageInfo.getRequest()
            # Get the request body
            body = self._helpers.bytesToString(request).split("\r\n\r\n", 1)[1]
            # Check if 'MFA_CODE' is in the body
            if 'MFA_CODE' in body:
                # Introduce delay
                time.sleep(30)

    def getActionName(self):
        return "Introduce Delay After Request"

    def performAction(self, currentRequestResponse):
        # This will be called when the action is selected
        self._callbacks.printOutput("Delay action invoked!")
        time.sleep(30)
