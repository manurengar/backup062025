*&---------------------------------------------------------------------*
*& Report ZHR_REPLACE_PA2001_TEXTS
*&---------------------------------------------------------------------*
REPORT zhr_replace_pa2001_texts.

TABLES: pa2001.

*----------------------------------------------------------------------*
* TYPES & DATA DECLARATIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_output,
         pernr    TYPE pernr_d,
         begda    TYPE begda,
         endda    TYPE endda,
         old_text TYPE string,
         new_text TYPE string,
       END OF ty_output.

DATA: gt_output TYPE TABLE OF ty_output.

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS: s_pernr FOR pa2001-pernr.
  PARAMETERS: p_begda TYPE begda OBLIGATORY DEFAULT sy-datum,
              p_endda TYPE endda OBLIGATORY DEFAULT '99991231'.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  " LOWER CASE addition prevents SAP from auto-capitalizing the inputs, 
  " allowing for exact case matching or case-insensitive searches.
  PARAMETERS: p_search TYPE string LOWER CASE, 
              p_repla  TYPE string LOWER CASE. 
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
* MAIN LOGIC
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM get_and_process_data.

END-OF-SELECTION.
  PERFORM display_alv.

*----------------------------------------------------------------------*
* FORM get_and_process_data
*----------------------------------------------------------------------*
FORM get_and_process_data.
  DATA: lt_pa2001 TYPE TABLE OF pa2001,
        ls_output TYPE ty_output,
        ls_pskey  TYPE pskey.

  " Fetch PA2001 records intersecting with dates and having texts (ITXEX = 'X')
  SELECT * FROM pa2001
    INTO TABLE @lt_pa2001
    WHERE pernr IN @s_pernr
      AND begda <= @p_endda
      AND endda >= @p_begda
      AND itxex = 'X'.

  LOOP AT lt_pa2001 INTO DATA(ls_pa2001).
    CLEAR ls_output.
    ls_output-pernr = ls_pa2001-pernr.
    ls_output-begda = ls_pa2001-begda.
    ls_output-endda = ls_pa2001-endda.

    " 1. Build the PSKEY required to read the HR text cluster
    ls_pskey-pernr = ls_pa2001-pernr.
    ls_pskey-infty = '2001'.
    ls_pskey-subty = ls_pa2001-subty.
    ls_pskey-objps = ls_pa2001-objps.
    ls_pskey-sprps = ls_pa2001-sprps.
    ls_pskey-endda = ls_pa2001-endda.
    ls_pskey-begda = ls_pa2001-begda.
    ls_pskey-seqnr = ls_pa2001-seqnr.

    " 2. Read the Text Cluster
    CALL METHOD cl_hrpa_text_cluster=>read
      EXPORTING
        tclas         = 'A'
        pskey         = ls_pskey
      IMPORTING
        text_tab      = DATA(lt_text)
      EXCEPTIONS
        error_occured = 1
        OTHERS        = 2.

    IF sy-subrc = 0.
      DATA(lv_old_text) = ``.

      " 3. Transform the cluster internal table into a continuous string
      " Using FIELD-SYMBOLS and dynamic assignments for maximum compatibility
      LOOP AT lt_text ASSIGNING FIELD-SYMBOL(<fs_text>).
        ASSIGN COMPONENT 'LINE' OF STRUCTURE <fs_text> TO FIELD-SYMBOL(<fs_line>).
        IF <fs_line> IS ASSIGNED.
          lv_old_text = lv_old_text && <fs_line> && ` `.
          UNASSIGN <fs_line>.
        ENDIF.
      ENDLOOP.

      " Clean up trailing spaces
      CONDENSE lv_old_text.
      ls_output-old_text = lv_old_text.

      " 4. Replace specific word/phrase using built-in ABAP function
      DATA(lv_new_text) = lv_old_text.
      IF p_search IS NOT INITIAL.
        REPLACE ALL OCCURRENCES OF p_search IN lv_new_text 
                WITH p_repla IGNORING CASE.
      ENDIF.

      ls_output-new_text = lv_new_text.

      " Append to ALV output table
      APPEND ls_output TO gt_output.

      " --------------------------------------------------------------------
      " OPTIONAL: If the prompt meant to update the text back to the database,
      " you would convert lv_new_text back to a table structure and call:
      "
      " CALL METHOD cl_hrpa_text_cluster=>update
      "   EXPORTING
      "     tclas         = 'A'
      "     pskey         = ls_pskey
      "     text_tab      = lt_updated_text " Must be converted back to table
      "     no_auth_check = 'X'
      "   ...
      " --------------------------------------------------------------------
    ENDIF.
  ENDLOOP.
ENDFORM.

*----------------------------------------------------------------------*
* FORM display_alv
*----------------------------------------------------------------------*
FORM display_alv.
  DATA: lo_alv TYPE REF TO cl_salv_table.

  IF gt_output IS INITIAL.
    MESSAGE 'No texts found for the given selection.' TYPE 'S'.
    RETURN.
  ENDIF.

  TRY.
      " Generate ALV using standard SALV classes
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = gt_output ).

      " Optimize column widths
      DATA(lo_columns) = lo_alv->get_columns( ).
      lo_columns->set_optimize( abap_true ).

      " Display the table
      lo_alv->display( ).

    CATCH cx_salv_msg.
      WRITE: / 'Error generating ALV output.'.
  ENDTRY.
ENDFORM.