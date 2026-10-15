#!/bin/zsh
export PATH="$HOME/flutter/bin:$PATH"
cd -- "${0:A:h}"
/usr/bin/python3 check_offline_odoo.py
