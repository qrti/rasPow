#! /usr/bin/env python
import os
import RPi.GPIO as GPIO

SHUT_ = 17      # GPIO17 pin 11 as input with pullup for shutdown
CHKRUN_ = 23    # GPIO23 pin 16 as output LOW for run check

GPIO.setmode(GPIO.BCM)
GPIO.setup(SHUT_, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(CHKRUN_, GPIO.OUT, initial=GPIO.LOW)

try:
    while True:
        GPIO.wait_for_edge(SHUT_, GPIO.FALLING)
        os.system("/sbin/shutdown -h now")
except:
    GPIO.cleanup()

# edit
# nano shutdown.py

# test
# sudo python3 shutdown.py

# auto crontab
# sudo nano /etc/crontab
# @reboot root /usr/bin/python /home/pi/shutdown.py
