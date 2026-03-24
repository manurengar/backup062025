*&---------------------------------------------------------------------*
*& Report  ZRPA2001_TEXT_REPLACE
*& Description: Read PA2001 absence comments from text cluster,
*&              search for a specific word and replace it with another.
*&              Output shows PERNR, BEGDA, ENDDA, original text and
*&              replaced text.
*&---------------------------------------------------------------------*
REPORT zrpa2001_text_replace.

*----------------------------------------------------------------------*
* TYPE DECLARATIONS
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_output,
    pernr    TYPE pernr_d,
    begda    TYPE begda,
    endda    TYPE endda,
    old_text TYPE string,
    new_text TYPE string,
  END OF ty_output.

*----------------------------------------------------------------------*
* DATA DECLARATIONS
*----------------------------------------------------------------------*
DATA:
  gt_output    TYPE STANDARD TABLE OF ty_output,
  gs_output    TYPE ty_output,
  gt_pa2001    TYPE STANDARD TABLE OF pa2001,
  gs_pa2001    TYPE pa2001,
  gv_text_orig TYPE string,
  gv_text_new  TYPE string,
  gv_found     TYPE abap_bool.

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  " Personnel numbers
  SELECT-OPTIONS: so_pernr FOR gs_pa2001-pernr NO INTERVALS.

  " Date range
  PARAMETERS:
    p_begda TYPE begda DEFAULT sy-datum,
    p_endda TYPE endda DEFAULT sy-datum.

  SELECTION-SCREEN SKIP 1.

  " Text search and replace
  PARAMETERS:
    p_search TYPE string LOWER CASE,
    p_replac TYPE string LOWER CASE.

SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  TEXT-001 = 'Selection Parameters'(001).

*----------------------------------------------------------------------*
* AT SELECTION SCREEN
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  " Validate that search text is not initial
  IF p_search IS INITIAL.
    MESSAGE 'Please enter a search text.' TYPE 'E'.
  ENDIF.

  " Validate date range
  IF p_begda > p_endda.
    MESSAGE 'Begin date cannot be greater than end date.' TYPE 'E'.
  ENDIF.

*----------------------------------------------------------------------*
* START OF SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.

  " Select PA2001 records matching selection criteria
  SELECT * FROM pa2001
    INTO TABLE gt_pa2001
    WHERE pernr IN so_pernr
      AND begda <= p_endda
      AND endda >= p_begda
      AND subty <> space.          " Only records with a subtype

  IF gt_pa2001 IS INITIAL.
    MESSAGE 'No PA2001 records found for the given selection.' TYPE 'I'.
    RETURN.
  ENDIF.

  " Process each PA2001 record
  LOOP AT gt_pa2001 INTO gs_pa2001.

    CLEAR: gs_output, gv_text_orig, gv_text_new, gv_found.

    " Try to read text from the HR text cluster
    PERFORM read_text_cluster USING    gs_pa2001
                              CHANGING gv_text_orig
                                       gv_found.

    IF gv_found = abap_true AND gv_text_orig IS NOT INITIAL.

      " Check if the search string exists in the text
      IF gv_text_orig CS p_search.

        " Replace all occurrences of the search string
        gv_text_new = gv_text_orig.
        REPLACE ALL OCCURRENCES OF p_search
                                IN gv_text_new
                             WITH p_replac
                    RESPECTING CASE.

        " Populate output structure
        gs_output-pernr    = gs_pa2001-pernr.
        gs_output-begda    = gs_pa2001-begda.
        gs_output-endda    = gs_pa2001-endda.
        gs_output-old_text = gv_text_orig.
        gs_output-new_text = gv_text_new.

        APPEND gs_output TO gt_output.

      ENDIF.
    ENDIF.

  ENDLOOP.

  IF gt_output IS INITIAL.
    MESSAGE 'No records found containing the search text.' TYPE 'I'.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* END OF SELECTION – Display ALV output
*----------------------------------------------------------------------*
END-OF-SELECTION.
  PERFORM display_alv.

*----------------------------------------------------------------------*
*& FORM read_text_cluster
*& Read the long text associated with a PA2001 record using the
*& CL_HRPA_TEXT_CLUSTER class.
*----------------------------------------------------------------------*
FORM read_text_cluster
  USING    is_pa2001    TYPE pa2001
  CHANGING cv_text      TYPE string
           cv_found     TYPE abap_bool.

  DATA:
    lo_text_cluster TYPE REF TO cl_hrpa_text_cluster,
    lt_text_lines   TYPE STANDARD TABLE OF tline,
    ls_text_line    TYPE tline,
    lv_text_chunk   TYPE string,
    lv_object_id    TYPE thead-tdname,
    lx_error        TYPE REF TO cx_root.

  cv_found = abap_false.
  CLEAR cv_text.

  TRY.
      " Create instance of text cluster class
      CREATE OBJECT lo_text_cluster.

      " Build the object ID for the text cluster
      " PA2001 text object key: PERNR + SUBTY + OBJPS + ISTAT + BEGDA
      CONCATENATE is_pa2001-pernr
                  is_pa2001-subty
                  is_pa2001-objps
                  is_pa2001-istat
                  is_pa2001-begda
             INTO lv_object_id.

      " Read the text cluster
      CALL METHOD cl_hrpa_text_cluster=>read
        EXPORTING
          pernr     = is_pa2001-pernr
          infty     = '2001'
          subty     = is_pa2001-subty
          objps     = is_pa2001-objps
          istat     = is_pa2001-istat
          begda     = is_pa2001-begda
          endda     = is_pa2001-endda
          seqnr     = is_pa2001-seqnr
        IMPORTING
          text_tab  = lt_text_lines.

      IF lt_text_lines IS NOT INITIAL.
        cv_found = abap_true.

        " Concatenate all text lines into a single string
        LOOP AT lt_text_lines INTO ls_text_line.
          lv_text_chunk = ls_text_line-tdline.
          IF cv_text IS INITIAL.
            cv_text = lv_text_chunk.
          ELSE.
            CONCATENATE cv_text lv_text_chunk
                   INTO cv_text
              SEPARATED BY space.
          ENDIF.
        ENDLOOP.

        " Clean up leading/trailing spaces
        CONDENSE cv_text.
      ENDIF.

    CATCH cx_root INTO lx_error.
      " Log error but continue processing other records
      MESSAGE lx_error->get_text( ) TYPE 'W'.
  ENDTRY.

ENDFORM.

*----------------------------------------------------------------------*
*& FORM display_alv
*& Display the output list using CL_SALV_TABLE
*----------------------------------------------------------------------*
FORM display_alv.

  DATA:
    lo_alv       TYPE REF TO cl_salv_table,
    lo_columns   TYPE REF TO cl_salv_columns_table,
    lo_column    TYPE REF TO cl_salv_column_table,
    lo_functions TYPE REF TO cl_salv_functions,
    lo_display   TYPE REF TO cl_salv_display_settings,
    lo_layout    TYPE REF TO cl_salv_layout,
    ls_layout_key TYPE salv_s_layout_key,
    lx_error     TYPE REF TO cx_salv_error.

  TRY.
      " Create ALV table
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = gt_output ).

      " Activate standard functions (sort, filter, export)
      lo_functions = lo_alv->get_functions( ).
      lo_functions->set_all( abap_true ).

      " Display settings
      lo_display = lo_alv->get_display_settings( ).
      lo_display->set_striped_pattern( abap_true ).
      lo_display->set_list_header( 'PA2001 Comment Text Search & Replace' ).

      " Configure columns
      lo_columns = lo_alv->get_columns( ).
      lo_columns->set_optimize( abap_true ).

      " PERNR column
      TRY.
          lo_column ?= lo_columns->get_column( 'PERNR' ).
          lo_column->set_short_text( 'Pers.No' ).
          lo_column->set_medium_text( 'Personnel No.' ).
          lo_column->set_long_text( 'Personnel Number' ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.

      " BEGDA column
      TRY.
          lo_column ?= lo_columns->get_column( 'BEGDA' ).
          lo_column->set_short_text( 'From' ).
          lo_column->set_medium_text( 'Start Date' ).
          lo_column->set_long_text( 'Start Date (BEGDA)' ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.

      " ENDDA column
      TRY.
          lo_column ?= lo_columns->get_column( 'ENDDA' ).
          lo_column->set_short_text( 'To' ).
          lo_column->set_medium_text( 'End Date' ).
          lo_column->set_long_text( 'End Date (ENDDA)' ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.

      " OLD_TEXT column
      TRY.
          lo_column ?= lo_columns->get_column( 'OLD_TEXT' ).
          lo_column->set_short_text( 'Orig.Text' ).
          lo_column->set_medium_text( 'Original Text' ).
          lo_column->set_long_text( 'Original Comment Text' ).
          lo_column->set_output_length( 80 ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.

      " NEW_TEXT column
      TRY.
          lo_column ?= lo_columns->get_column( 'NEW_TEXT' ).
          lo_column->set_short_text( 'New Text' ).
          lo_column->set_medium_text( 'Replaced Text' ).
          lo_column->set_long_text( 'Text After Replacement' ).
          lo_column->set_output_length( 80 ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.

      " Layout key for saving display variants
      ls_layout_key-report = sy-repid.
      lo_layout = lo_alv->get_layout( ).
      lo_layout->set_key( ls_layout_key ).
      lo_layout->set_save_restriction( cl_salv_layout=>restrict_none ).

      " Display ALV
      lo_alv->display( ).

    CATCH cx_salv_error INTO lx_error.
      MESSAGE lx_error->get_text( ) TYPE 'E'.
  ENDTRY.

ENDFORM.
