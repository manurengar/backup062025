" --------------------------------------------------------------------
      " 5. CONVERT STRING BACK TO TEXT TABLE
      " --------------------------------------------------------------------
      DATA: lt_updated_text LIKE lt_text, " Inherit exact type from READ method
            ls_updated_text LIKE LINE OF lt_updated_text,
            lv_str_len      TYPE i,
            lv_offset       TYPE i,
            lv_chunk_size   TYPE i.

      " Dynamically get the maximum allowed characters for the text line
      " (HRPAD_TEXT_TAB-LINE is typically 79 characters long)
      DESCRIBE FIELD ls_updated_text-line LENGTH lv_chunk_size IN CHARACTER MODE.

      lv_str_len = strlen( lv_new_text ).
      lv_offset  = 0.

      " Slice the string into chunks and append to the table
      WHILE lv_offset < lv_str_len.
        CLEAR ls_updated_text.
        
        IF ( lv_str_len - lv_offset ) > lv_chunk_size.
          ls_updated_text-line = lv_new_text+lv_offset(lv_chunk_size).
          lv_offset = lv_offset + lv_chunk_size.
        ELSE.
          ls_updated_text-line = lv_new_text+lv_offset.
          lv_offset = lv_str_len. " Force loop to end
        ENDIF.

        APPEND ls_updated_text TO lt_updated_text.
      ENDWHILE.

      " --------------------------------------------------------------------
      " 6. UPDATE THE TEXT CLUSTER
      " --------------------------------------------------------------------
      DATA: lv_is_ok TYPE boole_d.

      CALL METHOD cl_hrpa_text_cluster=>update
        EXPORTING
          tclas         = 'A'
          pskey         = ls_pskey
          text_tab      = lt_updated_text
          no_auth_check = 'X' " Bypasses auth check; remove if standard checks are required
        IMPORTING
          is_ok         = lv_is_ok.

      " Track update success in your ALV if desired
      IF lv_is_ok = abap_true.
        " Success: The update was buffered. 
        " Note: You must run a COMMIT WORK at the end of the report to save to DB.
      ELSE.
        " Handle update failure here
      ENDIF.
      " --------------------------------------------------------------------