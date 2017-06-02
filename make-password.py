#!/usr/bin/python

import crypt
import random
import hashlib
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('password',
                        type=str,
                        nargs=1)
    args = parser.parse_args()
    
    random.seed()
    print(crypt.crypt(args.password[0], "$6$" + hashlib.sha1(str(random.random())).hexdigest()))

if __name__ == "__main__":
    main()
    
