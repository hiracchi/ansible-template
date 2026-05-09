#!/usr/bin/python3                                                                                                                              
                                                                                                                                                
import getpass                                                                                                                                  
from passlib.hash import sha512_crypt                                                                                                           
                                                                                                                                                
def main():                                                                                                                                     
    pw = getpass.getpass()                                                                                                                      
    print(sha512_crypt.hash(pw))                                                                                                                
                                                                                                                                                
if __name__ == "__main__":                                                                                                                      
    main()                                                                                                                                      
                                                                                                                                                
