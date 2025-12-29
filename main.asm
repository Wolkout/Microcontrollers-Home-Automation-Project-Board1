;====================================================================
; PROJE: Ev Otomasyonu - Board #1
; GÖREV: 2.1.1 Termostat ve Fan Kontrolü
; YAZAR: Abdullah Esad Özçelik
; TARIH: 2025 Sonbahar Dönemi
;====================================================================

    LIST P=16F877A
    INCLUDE "P16F877A.INC"
    
    ; Ayarlar
    __CONFIG _FOSC_HS & _WDTE_OFF & _PWRTE_ON & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _WRT_OFF & _CP_OFF
    

;====================================================================
; DEGISKENLER (RAM)
;====================================================================
    CBLOCK 0x20
        ; --- GIRIS DEGISKENLERI ---
        SET_TEMP_INT        ; Tam sayi kismi
        SET_TEMP_DEC        ; Ondalik kismi

        ; --- ISLEM DEGISKENLERI ---
        TARGET_VAL_L        
        TARGET_VAL_H        
        
        CURRENT_VAL_L       
        CURRENT_VAL_H       

        FAN_SPEED           
        
        ; --- GEÇICI SAYAÇLAR ---
        COUNT1
        COUNT2
        TEMP_MATH_L
        TEMP_MATH_H
    ENDC

    ORG 0x00
    GOTO START

;====================================================================
; AYARLAR (SETUP)
;====================================================================
START:
    ; --- BANK 1 ---
    BSF STATUS, RP0
    BCF STATUS, RP1
    
    MOVLW 0x07
    MOVWF CMCON             ; Komparatörleri kapa
    
    MOVLW B'10001110'       ; RA0 Analog
    MOVWF ADCON1
    
    MOVLW B'00000000'       ; PORTD Çikis
    MOVWF TRISD
    
    MOVLW B'00010001'       ; RA0, RA4 Giris
    MOVWF TRISA
    
    MOVLW B'00101000'       ; Timer0 Ayari
    MOVWF OPTION_REG

    ; --- BANK 0 ---
    BCF STATUS, RP0
    
    MOVLW B'10000001'       ; ADC Açik
    MOVWF ADCON0

    ;================================================================
    ; TEST DEGERLERI (Keypad gelince silinecek)
    ;================================================================
    MOVLW D'25'             ; Hedef tam kismi: 25 derece
    MOVWF SET_TEMP_INT
    
    MOVLW D'3'              ; Hedef ondalik kismi: .3 (Toplam 25.3)
    MOVWF SET_TEMP_DEC
    ;================================================================

;====================================================================
; ANA DÖNGÜ
;====================================================================
MAIN_LOOP:
    CALL CALC_TARGET_TENTHS   ; Hedefi hazirla
    CALL READ_SENSOR_PRECISE  ; Sensörü oku
    CALL MEASURE_FAN_SPEED    ; Fani ölç

    ; --- KARSILASTIRMA (16 Bit) ---
    ; Hedef - Ortam islemi
    MOVF CURRENT_VAL_L, W
    SUBWF TARGET_VAL_L, W
    MOVWF TEMP_MATH_L       
    
    MOVF CURRENT_VAL_H, W
    BTFSS STATUS, C         ; Borç var mi?
    ADDLW 1                 ; Varsa düs?
    SUBWF TARGET_VAL_H, W

    ; SONUÇ: C=1 (Isit), C=0 (Sogut)
    BTFSS STATUS, C
    GOTO SOGUTMA_MODU
    GOTO ISITMA_MODU

ISITMA_MODU:
    BSF PORTD, 0            ; Isitici AÇ
    BCF PORTD, 1            ; Fan KAPAT
    GOTO DONGU_SONU

SOGUTMA_MODU:
    BCF PORTD, 0            ; Isitici KAPAT
    BSF PORTD, 1            ; Fan AÇ
    GOTO DONGU_SONU

DONGU_SONU:
    GOTO MAIN_LOOP

;====================================================================
; SUBROUTINE : HEDEF HESAPLA (Tam*10 + Ondalik)
;====================================================================
CALC_TARGET_TENTHS:
    ; X2
    MOVF SET_TEMP_INT, W
    MOVWF TEMP_MATH_L
    CLRF TEMP_MATH_H
    BCF STATUS, C
    RLF TEMP_MATH_L, F
    RLF TEMP_MATH_H, F      
    
    ; Kaydet
    MOVF TEMP_MATH_L, W
    MOVWF TARGET_VAL_L
    MOVF TEMP_MATH_H, W
    MOVWF TARGET_VAL_H

    ; X8 (X2'den devam)
    BCF STATUS, C
    RLF TEMP_MATH_L, F      
    RLF TEMP_MATH_H, F
    BCF STATUS, C
    RLF TEMP_MATH_L, F      
    RLF TEMP_MATH_H, F
    
    ; Topla (X8 + X2)
    MOVF TARGET_VAL_L, W
    ADDWF TEMP_MATH_L, F
    BTFSC STATUS, C
    INCF TEMP_MATH_H, F
    MOVF TARGET_VAL_H, W
    ADDWF TEMP_MATH_H, F
    
    ; Ondalik Ekle
    MOVF SET_TEMP_DEC, W
    ADDWF TEMP_MATH_L, F
    BTFSC STATUS, C
    INCF TEMP_MATH_H, F

    ; Sonuç
    MOVF TEMP_MATH_L, W
    MOVWF TARGET_VAL_L
    MOVF TEMP_MATH_H, W
    MOVWF TARGET_VAL_H
    RETURN

;====================================================================
; SUBROUTINE : SENSÖR OKU (ADC*5)
;====================================================================
READ_SENSOR_PRECISE:
    MOVLW D'50'
    MOVWF COUNT1
DELAY_ADC:
    DECFSZ COUNT1, F
    GOTO DELAY_ADC
    BSF ADCON0, GO
WAIT_ADC:
    BTFSC ADCON0, GO
    GOTO WAIT_ADC

    BSF STATUS, RP0
    MOVF ADRESL, W
    BCF STATUS, RP0
    MOVWF CURRENT_VAL_L
    MOVF ADRESH, W
    MOVWF CURRENT_VAL_H

    ; ADC * 5 = (ADC*4) + ADC
    MOVF CURRENT_VAL_L, W
    MOVWF TEMP_MATH_L
    MOVF CURRENT_VAL_H, W
    MOVWF TEMP_MATH_H

    BCF STATUS, C
    RLF CURRENT_VAL_L, F
    RLF CURRENT_VAL_H, F    ; x2
    BCF STATUS, C
    RLF CURRENT_VAL_L, F
    RLF CURRENT_VAL_H, F    ; x4
    
    MOVF TEMP_MATH_L, W
    ADDWF CURRENT_VAL_L, F
    BTFSC STATUS, C
    INCF CURRENT_VAL_H, F
    MOVF TEMP_MATH_H, W
    ADDWF CURRENT_VAL_H, F
    
    RETURN

;====================================================================
; SUBROUTINE : FAN HIZI
;====================================================================
MEASURE_FAN_SPEED:
    CLRF TMR0
    MOVLW D'100'
    MOVWF COUNT1
HIZ_GECIKME:
    MOVLW D'250'
    MOVWF COUNT2
HIZ_LOOP:
    DECFSZ COUNT2, F
    GOTO HIZ_LOOP
    DECFSZ COUNT1, F
    GOTO HIZ_GECIKME
    MOVF TMR0, W
    MOVWF FAN_SPEED
    RETURN

    END


