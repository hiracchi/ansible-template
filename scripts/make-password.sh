#!/bin/bash

# SHA-512 パスワードハッシュを生成するスクリプト (Linux /etc/shadow 形式)
# OpenSSL を使用して $6$... 形式のハッシュを作成します

openssl passwd -6
