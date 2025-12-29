;====================================================================
; PROJE: Ev Otomasyonu - Board #2
; GÖREV: 2.1.1 2.2.4 Step Motor ve Potansiyometre Kontrolü
; YAZAR: Abdullah Esad Özçelik
; TARIH: 2025 Sonbahar Dönemi
;====================================================================

    LIST P=16F877A
    INCLUDE "P16F877A.INC"

    __CONFIG _FOSC_HS & _WDTE_OFF & _PWRTE_ON & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _WRT_OFF & _CP_OFF
    
    ERRORLEVEL -302

;====================================================================
; DEGISKENLER
;====================================================================
    CBLOCK 0x20
        ; --- ENTEGRASYON DEGISKENI (ARKADASIMDAN GELECEK) ---
        LDR_FLAG            ; 1=Karanlik, 0=Aydinlik
        
        ; --- BENIM DEGISKENLERIM ---
        LDR_VAL             ; (Simülasyon için geçici)
        POT_VAL             
        TAR_POS_L           
        TAR_POS_H           
        CUR_POS_L           
        CUR_POS_H           
        STEP_INDEX          
        DELAY_VAR1, DELAY_VAR2
        SPEED_VAL           
        IS_RETURNING
    ENDC

    LDR_THRESHOLD EQU D'50' 
    MAX_STEP_L    EQU 0xD0  ; 2000 Adim (Low)
    MAX_STEP_H    EQU 0x07  ; 2000 Adim (High)

    ORG 0x00
    GOTO START

;====================================================================
; AYARLAR
;====================================================================
START:
    BSF STATUS, RP0
    BCF STATUS, RP1
    MOVLW 0x06
    MOVWF ADCON1
    MOVLW B'00000100'       ; AN0, AN1 Analog
    MOVWF ADCON1
    MOVLW B'00000011'       
    MOVWF TRISA
    MOVLW B'00000000'       
    MOVWF TRISB
    BCF STATUS, RP0
    MOVLW B'10000001'
    MOVWF ADCON0

    CLRF CUR_POS_L
    CLRF CUR_POS_H
    CLRF STEP_INDEX
    CLRF PORTB
    CLRF IS_RETURNING

;====================================================================
; ANA DÖNGÜ
;====================================================================
MAIN_LOOP:

    ; ---------------------------------------------------------------
    ; [AKTIF] SIMÜLASYON MODU (Su an çalisan kisim)
    ; Birlesme zamani bu blok devreden çikacak.
    ; ---------------------------------------------------------------
    CALL SIMULATION_READ_LDR 
    MOVF LDR_VAL, W
    SUBLW LDR_THRESHOLD
    BTFSC STATUS, C         ; Aydinlik mi?
    GOTO MOD_GUNDUZ         ; Evetse Gündüz
    ; Hayirsa asagi devam et (Gece)...


    ; ---------------------------------------------------------------
    ; [PASIF] ENTEGRASYON MODU (Birlesme günü burasi devreye sokulacak)
    ; LDR_FLAG adresine ne yazdigina bak.
    ; ---------------------------------------------------------------
    ;
    ; MOVF LDR_FLAG, W      ; Arkadaimmin bayragini W'ye al
    ; BTFSC STATUS, Z       ; Eger 0 ise (Z=1 olur) -> GÜNDÜZ
    ; GOTO MOD_GUNDUZ       ; Gündüz moduna git
    ;
    ; ; Eger 0 degilse (yani 1 ise), buraya düser -> GECE
    ; ---------------------------------------------------------------


    ; --- GECE MODU (LDR_FLAG = 1 ?SE BURASI ÇALISIR) ---
    MOVLW D'1'
    MOVWF IS_RETURNING      ; Otomatik dönüs bayragini kaldir
    
    MOVLW D'50'
    MOVWF SPEED_VAL         ; Hiz: Yavas (Sinematik)
    
    MOVLW MAX_STEP_L        ; Hedef: Tam Kapali
    MOVWF TAR_POS_L
    MOVLW MAX_STEP_H
    MOVWF TAR_POS_H
    GOTO MOTOR_HAREKET

MOD_GUNDUZ:
    ; --- GÜNDÜZ MODU (LDR_FLAG = 0 ISE BURASI ÇALISIR) ---
    
    MOVLW D'2'              ; Hiz: Hizli
    MOVWF SPEED_VAL
    
    CALL READ_MY_POT
    
    ; (POT * 8) Hesapla
    MOVF POT_VAL, W
    MOVWF TAR_POS_L
    CLRF TAR_POS_H          
    BCF STATUS, C
    RLF TAR_POS_L, F        ; x2
    RLF TAR_POS_H, F
    BCF STATUS, C
    RLF TAR_POS_L, F        ; x4
    RLF TAR_POS_H, F
    BCF STATUS, C
    RLF TAR_POS_L, F        ; x8
    RLF TAR_POS_H, F

    ; Tiraslama: (POT / 6) ç?kar (3.00V Kalibrasyonu)
    ; POT/8
    MOVF POT_VAL, W
    MOVWF DELAY_VAR1
    BCF STATUS, C
    RRF DELAY_VAR1, F       ; /2
    BCF STATUS, C
    RRF DELAY_VAR1, F       ; /4
    BCF STATUS, C
    RRF DELAY_VAR1, F       ; /8
    ; POT/32
    MOVF POT_VAL, W
    MOVWF DELAY_VAR2
    BCF STATUS, C
    RRF DELAY_VAR2, F       ; /2
    BCF STATUS, C
    RRF DELAY_VAR2, F       ; /4
    BCF STATUS, C
    RRF DELAY_VAR2, F       ; /8
    BCF STATUS, C
    RRF DELAY_VAR2, F       ; /16
    BCF STATUS, C
    RRF DELAY_VAR2, F       ; /32
    ; Topla ve Ç?kar
    MOVF DELAY_VAR2, W
    ADDWF DELAY_VAR1, W
    SUBWF TAR_POS_L, F      
    BTFSS STATUS, C         
    DECF TAR_POS_H, F

    ; Vardik mi kontrolü
    MOVF CUR_POS_L, W
    SUBWF TAR_POS_L, W
    BTFSS STATUS, Z
    GOTO HIZI_AYARLA        
    MOVF CUR_POS_H, W
    SUBWF TAR_POS_H, W
    BTFSS STATUS, Z
    GOTO HIZI_AYARLA        
    CLRF IS_RETURNING       ; Vardik, bayragi indir.

HIZI_AYARLA:
    MOVF IS_RETURNING, W
    BTFSC STATUS, Z         ; Bayrak 0 ise HIZLI
    GOTO HIZLI_MOD
    MOVLW D'50'             ; Bayrak 1 ise YAVAS
    MOVWF SPEED_VAL
    GOTO MOTOR_HAREKET

HIZLI_MOD:
    MOVLW D'2'
    MOVWF SPEED_VAL

MOTOR_HAREKET:
    MOVF CUR_POS_H, W
    SUBWF TAR_POS_H, W
    BTFSS STATUS, Z         
    GOTO CHECK_CARRY_H      
    MOVF CUR_POS_L, W
    SUBWF TAR_POS_L, W
    BTFSC STATUS, Z         
    GOTO DONGU_SONU         
    BTFSS STATUS, C         
    GOTO GIT_GERI
    GOTO GIT_ILERI

CHECK_CARRY_H:
    BTFSS STATUS, C         
    GOTO GIT_GERI
    GOTO GIT_ILERI

GIT_ILERI:
    CALL STEP_FORWARD
    INCF CUR_POS_L, F
    BTFSC STATUS, Z         
    INCF CUR_POS_H, F       
    GOTO DONGU_SONU

GIT_GERI:
    CALL STEP_BACKWARD
    MOVF CUR_POS_L, W       
    BTFSC STATUS, Z         
    DECF CUR_POS_H, F       
    DECF CUR_POS_L, F       
    GOTO DONGU_SONU

DONGU_SONU:
    CALL DELAY_VARIABLE      
    GOTO MAIN_LOOP

;====================================================================
; SUBROUTINELER
;====================================================================
READ_MY_POT:
    MOVLW B'10001001'       
    MOVWF ADCON0
    CALL DELAY_SHORT
    BSF ADCON0, GO
WAIT_POT:
    BTFSC ADCON0, GO
    GOTO WAIT_POT
    MOVF ADRESH, W
    MOVWF POT_VAL
    RETURN

SIMULATION_READ_LDR:
    MOVLW B'10000001'       
    MOVWF ADCON0
    CALL DELAY_SHORT
    BSF ADCON0, GO
WAIT_LDR:
    BTFSC ADCON0, GO
    GOTO WAIT_LDR
    MOVF ADRESH, W
    MOVWF LDR_VAL
    RETURN

STEP_FORWARD:
    INCF STEP_INDEX, F
    MOVLW D'8'
    SUBWF STEP_INDEX, W
    BTFSC STATUS, C
    CLRF STEP_INDEX
    GOTO SEND_STEP

STEP_BACKWARD:
    MOVF STEP_INDEX, W
    BTFSC STATUS, Z
    GOTO WRAP_STEP
    DECF STEP_INDEX, F
    GOTO SEND_STEP
WRAP_STEP:
    MOVLW D'7'
    MOVWF STEP_INDEX
    GOTO SEND_STEP

SEND_STEP:
    MOVF STEP_INDEX, W
    CALL GET_STEP_TABLE
    MOVWF PORTB
    RETURN

GET_STEP_TABLE:
    ADDWF PCL, F
    RETLW B'00001000'
    RETLW B'00001100'
    RETLW B'00000100'
    RETLW B'00000110'
    RETLW B'00000010'
    RETLW B'00000011'
    RETLW B'00000001'
    RETLW B'00001001'

DELAY_VARIABLE:
    MOVF SPEED_VAL, W       
    MOVWF DELAY_VAR1        
LOOP_F1:
    MOVLW D'50'             
    MOVWF DELAY_VAR2
LOOP_F2:
    DECFSZ DELAY_VAR2, F
    GOTO LOOP_F2
    DECFSZ DELAY_VAR1, F    
    GOTO LOOP_F1
    RETURN

DELAY_SHORT:
    MOVLW D'10'
    MOVWF DELAY_VAR1
LOOP_S:
    DECFSZ DELAY_VAR1, F
    GOTO LOOP_S
    RETURN

    END