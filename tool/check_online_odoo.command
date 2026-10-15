#!/bin/zsh
cd -- "${0:A:h}"
/usr/bin/python3 check_online_odoo.py
read -r '?Press Return to close this window.'
