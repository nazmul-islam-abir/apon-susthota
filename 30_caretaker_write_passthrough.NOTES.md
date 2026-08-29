I want to make a major update to my app by introducing a new two-role user system: Patient and Caretaker.

The main concept is very simple:

The Patient records their health information, while the Caretaker monitors and supports the Patient.

1. Two Types of Users

The app should now support two different user roles during signup/login:

Patient

The Patient is the person who uses the app to record their daily health information.

They can record and track things such as:

🍽️ Meals and food intake
💧 Water intake
🏃 Workout/exercise
💊 Medicine
🩸 Blood sugar
❤️ Blood pressure
📊 Daily health activities
Other existing health information in the app

The Patient should continue using the app normally to manage and track their own health.

Caretaker

The Caretaker is someone who takes care of or monitors a Patient.

Examples:

Son
Daughter
Husband/wife
Family member
Other trusted person

The Caretaker should have a different dashboard and experience focused on monitoring the connected Patient rather than recording their own health information.

2. Patient-Caretaker Connection

Add a new feature that allows a Caretaker to connect with a Patient.

For example:

A son creates a Caretaker account and wants to monitor his father.

The Caretaker should be able to:

Login as a Caretaker.
Select "Connect with Patient".
Enter the Patient's mobile number.
Find the Patient.
Send a connection request.
The Patient receives the request.
The Patient can Accept or Reject the request.
Only after the Patient accepts, the connection becomes active.

The Patient must always have control over whether someone can monitor their information.

3. Connected Patient

After the Patient accepts the request, the Caretaker should see the Patient in a section such as:

My Patients

For example:

Father — Connected

The Caretaker can then open the Patient's profile and access their monitoring dashboard.

4. Caretaker Monitoring Dashboard

Create a proper, easy-to-understand Patient Monitoring Dashboard for the Caretaker.

The dashboard should provide an overall view of how the Patient is doing.

For example:

Today's Overview
🍽️ Meals — Completed / Missed
💧 Water — Progress toward daily goal
🏃 Workout — Completed / Missed
💊 Medicine — Taken / Missed
🩸 Blood Sugar — Latest information
❤️ Blood Pressure — Latest information
📊 Overall daily activity

The Caretaker should be able to quickly understand:

"How is my father/mother doing today?"

without having to manually check every individual activity.

5. Activity Monitoring

The Caretaker should be able to monitor whether the Patient is maintaining their daily routine.

For example:

Meals

Show whether the Patient is regularly recording and following their meals.

Water

Show today's water intake and progress.

Workout

Show whether the Patient completed their planned workout.

Medicine

Show medicine activity where supported by the existing app.

Health Data

Show relevant blood sugar, blood pressure, and other health information already being tracked.

6. Daily / Weekly / Monthly View

The Caretaker should not only see today's information.

They should also be able to view:

Daily

What did the Patient do today?

Weekly

How consistently has the Patient been following their routine this week?

Monthly

What has the Patient's overall activity looked like over the month?

Use clear charts, progress indicators, and summaries where appropriate.