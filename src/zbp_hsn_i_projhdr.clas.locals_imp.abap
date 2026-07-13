*CLASS lhc_Header DEFINITION INHERITING FROM cl_abap_behavior_handler.
*  PRIVATE SECTION.
*    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
*      IMPORTING REQUEST requested_authorizations FOR Header
*      RESULT result.
*
*    METHODS getProjectData FOR MODIFY
*      IMPORTING keys FOR ACTION Header~getProjectData.
*
*    METHODS calcQuantities FOR DETERMINE ON MODIFY
*      IMPORTING keys FOR Item~calcQuantities.
*
*    METHODS validateOverBilling FOR VALIDATE ON SAVE
*      IMPORTING keys FOR Item~validateOverBilling.
*
*ENDCLASS.
*
*CLASS lhc_Header IMPLEMENTATION.
*
*
*METHOD calcQuantities.
*
*    " read the items being changed (in the draft)
*    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*      ENTITY Item ALL FIELDS WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_items).
*
*    DATA lt_update TYPE TABLE FOR UPDATE ZHSN_I_ProjItm.
*
*    LOOP AT lt_items INTO DATA(ls_item).
*
*      " 1. previously-saved consumed = SUM of tobe_billed already in the DB
*      "    for the same ProjectID + WorkPackageID, excluding this row
*      SELECT SUM( tobe_billed_quantity )
*        FROM zhsn_proj_itm
*        WHERE project_id     = @ls_item-ProjectID
*          AND workpackage_id = @ls_item-WorkPackageID
*          AND item_uuid     <> @ls_item-ItemUuid
*        INTO @DATA(lv_prev_consumed).
*
*      " 2. consumed = previously saved + what user is entering now
*      DATA(lv_consumed) = lv_prev_consumed + ls_item-TobeBilledQty.
*
*      " 3. balance = total (from API) - consumed
*      DATA(lv_balance) = ls_item-UnitQty - lv_consumed.
*
*      APPEND VALUE #(
*        %tky        = ls_item-%tky
*        ConsumeQty  = lv_consumed
*        BalnacedQty = lv_balance
*      ) TO lt_update.
*
*    ENDLOOP.
*
*    IF lt_update IS NOT INITIAL.
*      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*        ENTITY Item UPDATE FIELDS ( ConsumeQty BalnacedQty )
*                    WITH lt_update
*        REPORTED DATA(lt_rep).
*    ENDIF.
*
*  ENDMETHOD.
*
*
*  METHOD validateOverBilling.
*
*    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*      ENTITY Item ALL FIELDS WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_items).
*
*    LOOP AT lt_items INTO DATA(ls_item).
*
*      SELECT SUM( tobe_billed_quantity )
*        FROM zhsn_proj_itm
*        WHERE project_id     = @ls_item-ProjectID
*          AND workpackage_id = @ls_item-WorkPackageID
*          AND item_uuid     <> @ls_item-ItemUuid
*        INTO @DATA(lv_prev_consumed).
*
*      DATA(lv_consumed) = lv_prev_consumed + ls_item-TobeBilledQty.
*
*      " negative check
*      IF ls_item-TobeBilledQty < 0.
*        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-item.
*        APPEND VALUE #( %tky = ls_item-%tky
*          %element-TobeBilledQty = if_abap_behv=>mk-on
*          %msg = new_message_with_text(
*                   severity = if_abap_behv_message=>severity-error
*                   text = 'To Be Billed Qty cannot be negative' ) ) TO reported-item.
*        CONTINUE.
*      ENDIF.
*
*      " over-billing check: consumed must not exceed total
*      IF lv_consumed > ls_item-UnitQty.
*        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-item.
*        APPEND VALUE #( %tky = ls_item-%tky
*          %element-TobeBilledQty = if_abap_behv=>mk-on
*          %msg = new_message_with_text(
*                   severity = if_abap_behv_message=>severity-error
*                   text = |Over-billing: consumed { lv_consumed } exceeds total { ls_item-UnitQty }| ) )
*          TO reported-item.
*      ENDIF.
*
*    ENDLOOP.
*
*  ENDMETHOD.
*
*
*
*
*
*  METHOD get_global_authorizations.
*  ENDMETHOD.
*
*  METHOD getProjectData.
*
*    " 1. read ProjectID from the current draft
*    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*      ENTITY Header FIELDS ( ProjectID ) WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_headers).
*
*    " 2. delete existing children first (safe re-run)
*    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*      ENTITY Header BY \_Item FIELDS ( ItemUuid ) WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_existing).
*
*    IF lt_existing IS NOT INITIAL.
*      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*        ENTITY Item DELETE FROM VALUE #( FOR e IN lt_existing ( %tky = e-%tky ) )
*        REPORTED DATA(lt_rep_del).
*    ENDIF.
*
*    DATA lt_hdr_update TYPE TABLE FOR UPDATE ZHSN_I_ProjHdr.
*    DATA lt_create_by  TYPE TABLE FOR CREATE ZHSN_I_ProjHdr\_Item.
*
*    LOOP AT lt_headers INTO DATA(ls_hdr).
*
*      IF ls_hdr-ProjectID IS INITIAL.
*        APPEND VALUE #( %tky = ls_hdr-%tky
*          %msg = new_message_with_text(
*                   severity = if_abap_behv_message=>severity-error
*                   text = 'Select a Project ID first' ) ) TO reported-header.
*        CONTINUE.
*      ENDIF.
*
*      TRY.
*          NEW zcl_hsn_proj_api_reader( )->get_project_by_id(
*            EXPORTING iv_project_id = CONV #( ls_hdr-ProjectID )
*            IMPORTING es_project = DATA(ls_api) ev_found = DATA(lv_found) ).
*        CATCH cx_web_http_client_error cx_http_dest_provider_error INTO DATA(lx).
*          APPEND VALUE #( %tky = ls_hdr-%tky
*            %msg = new_message_with_text(
*                     severity = if_abap_behv_message=>severity-error
*                     text = |API failed: { lx->get_text( ) }| ) ) TO reported-header.
*          CONTINUE.
*      ENDTRY.
*
*      IF lv_found = abap_false.
*        APPEND VALUE #( %tky = ls_hdr-%tky
*          %msg = new_message_with_text(
*                   severity = if_abap_behv_message=>severity-warning
*                   text = |No project found for { ls_hdr-ProjectID }| ) ) TO reported-header.
*        CONTINUE.
*      ENDIF.
*
*      " 3. header field update
*      APPEND VALUE #(
*        %tky = ls_hdr-%tky
*        ProjectName = ls_api-projectname   ProjectStage = ls_api-projectstage
*        OrgID = ls_api-orgid               Currency = ls_api-currency
*        Customer = ls_api-customer         CostCenter = ls_api-costcenter
*        ProfitCenter = ls_api-profitcenter StartDate = ls_api-startdate
*        EndDate = ls_api-enddate           ProjectDesc = ls_api-projectdesc
*      ) TO lt_hdr_update.
*
*      " 4. create-by-association — carry the draft flag onto parent ref and children
*      APPEND VALUE #(
*        %tky-ProjUuid  = ls_hdr-%tky-ProjUuid
*        %tky-%is_draft = ls_hdr-%tky-%is_draft
*        %target = VALUE #( FOR ls_wp IN ls_api-workpackages INDEX INTO i (
*                    %cid            = |WP{ i }_{ ls_hdr-%tky-ProjUuid }|
*                    %is_draft       = ls_hdr-%tky-%is_draft
*                    ProjectID       = ls_wp-projectid
*                    WorkPackageID   = ls_wp-workpackageid
*                    WorkPackageName = ls_wp-workpackagename
*                    Description     = ls_wp-description
*                    WPStartDate     = ls_wp-wpstartdate
*                    WPEndDate       = ls_wp-wpenddate
*                    UnitQty         = ls_wp-unitquantity ) )
*      ) TO lt_create_by.
*
*    ENDLOOP.
*
*    " 5a. header update
*    IF lt_hdr_update IS NOT INITIAL.
*      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*        ENTITY Header UPDATE FIELDS ( ProjectName ProjectStage OrgID Currency Customer
*                                      CostCenter ProfitCenter StartDate EndDate ProjectDesc )
*                      WITH lt_hdr_update
*        REPORTED DATA(lt_rep_upd).
*    ENDIF.
*
*" 5b. create children
*    IF lt_create_by IS NOT INITIAL.
*      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*        ENTITY Header CREATE BY \_Item FIELDS ( ProjectID WorkPackageID WorkPackageName
*                                                Description WPStartDate WPEndDate UnitQty )
*                      WITH lt_create_by
*        REPORTED DATA(lt_rep_cre).
*    ENDIF.
*
*  ENDMETHOD.
*
*ENDCLASS.



CLASS lhc_Header DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Header
      RESULT result.

    METHODS getProjectData FOR MODIFY
      IMPORTING keys FOR ACTION Header~getProjectData.

    METHODS calcQuantities FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Item~calcQuantities.

    METHODS validateOverBilling FOR VALIDATE ON SAVE
      IMPORTING keys FOR Item~validateOverBilling.

METHODS uploadExcel FOR MODIFY
      IMPORTING keys FOR ACTION Header~uploadExcel RESULT result.

      METHODS activityAllocation FOR MODIFY
      IMPORTING keys FOR ACTION Header~activityAllocation RESULT result.

ENDCLASS.

CLASS lhc_Header IMPLEMENTATION.

METHOD activityAllocation.

    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
      ENTITY Header ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_hdr).

    DATA lt_upd TYPE TABLE FOR UPDATE ZHSN_I_ProjHdr.

    LOOP AT lt_hdr INTO DATA(ls_hdr).

      NEW zcl_hsn_act_alloc_post( )->post_allocation(
        IMPORTING ev_status   = DATA(lv_status)
                  ev_refdoc   = DATA(lv_refdoc)
                  ev_response = DATA(lv_resp) ).

      APPEND VALUE #(
        %tky              = ls_hdr-%tky
        ReferenceDocument = lv_refdoc
        AllocStatus       = lv_status
        AllocResponse     = lv_resp
      ) TO lt_upd.

*      APPEND VALUE #( %tky = ls_hdr-%tky
*        %msg = new_message_with_text(
*                 severity = COND #( WHEN lv_status = 'SUCCESS'
*                                    THEN if_abap_behv_message=>severity-success
*                                    ELSE if_abap_behv_message=>severity-error )
*                 text = |Allocation { lv_status }: { lv_refdoc }| ) ) TO reported-header.

IF lv_status <> 'SUCCESS'.
        APPEND VALUE #( %tky = ls_hdr-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text = |Allocation failed: { lv_resp }| ) ) TO reported-header.
      ENDIF.

    ENDLOOP.

    IF lt_upd IS NOT INITIAL.
      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
        ENTITY Header UPDATE FIELDS ( ReferenceDocument AllocStatus AllocResponse )
                      WITH lt_upd
        REPORTED DATA(lt_rep).
    ENDIF.

    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
      ENTITY Header ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_final).
    result = VALUE #( FOR h IN lt_final ( %tky = h-%tky %param = h ) ).

  ENDMETHOD.

METHOD uploadExcel.

  " row structure: columns A..G (we only use A and G)
  TYPES: BEGIN OF ty_xls,
           wp_id   TYPE string,   " A - WorkPackageID
           wp_name TYPE string,   " B
           wp_desc TYPE string,   " C
           unitq   TYPE string,   " D
           consq   TYPE string,   " E
           balq    TYPE string,   " F
           billq   TYPE string,   " G - TobeBilledQty
         END OF ty_xls.

  READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
    ENTITY Header FIELDS ( Attachment ) WITH CORRESPONDING #( keys )
    RESULT DATA(lt_hdr).

  READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
    ENTITY Header BY \_Item ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(lt_items).

  DATA lt_update TYPE TABLE FOR UPDATE ZHSN_I_ProjItm.

  LOOP AT lt_hdr INTO DATA(ls_hdr).

    IF ls_hdr-Attachment IS INITIAL.
      APPEND VALUE #( %tky = ls_hdr-%tky
        %msg = new_message_with_text(
                 severity = if_abap_behv_message=>severity-error
                 text = 'No file attached.' ) ) TO reported-header.
      CONTINUE.
    ENDIF.

    " parse xlsx with XCO (same reader as your working package)
    DATA lt_rows TYPE STANDARD TABLE OF ty_xls WITH DEFAULT KEY.
    CLEAR lt_rows.
    TRY.
        DATA(lo_read)  = xco_cp_xlsx=>document->for_file_content(
                           ls_hdr-Attachment )->read_access( ).
        DATA(lo_sheet) = lo_read->get_workbook( )->worksheet->at_position( 1 ).
        lo_sheet->select(
          xco_cp_xlsx_selection=>pattern_builder->simple_from_to(
            )->from_row( xco_cp_xlsx=>coordinate->for_numeric_value( 2 )
            )->from_column( xco_cp_xlsx=>coordinate->for_alphabetic_value( 'A' )
            )->to_column(   xco_cp_xlsx=>coordinate->for_alphabetic_value( 'G' )
            )->get_pattern( )
        )->row_stream( )->operation->write_to( REF #( lt_rows ) )->execute( ).
      CATCH cx_root INTO DATA(lx).
        APPEND VALUE #( %tky = ls_hdr-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text = |Excel read failed: { lx->get_text( ) }| ) ) TO reported-header.
        CONTINUE.
    ENDTRY.

    DELETE lt_rows WHERE wp_id IS INITIAL.

    " match by WorkPackageID, write TobeBilledQty
    LOOP AT lt_rows INTO DATA(ls_row).

      READ TABLE lt_items INTO DATA(ls_item)
        WITH KEY WorkPackageID = ls_row-wp_id.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DATA lv_qty TYPE p LENGTH 15 DECIMALS 3.
      CLEAR lv_qty.
      DATA(lv_clean) = condense( ls_row-billq ).
      IF lv_clean CO '0123456789.- ' AND lv_clean IS NOT INITIAL.
        lv_qty = CONV #( lv_clean ).
      ENDIF.

      APPEND VALUE #(
        %tky          = ls_item-%tky
        TobeBilledQty = lv_qty
        %control-TobeBilledQty = if_abap_behv=>mk-on
      ) TO lt_update.

    ENDLOOP.

  ENDLOOP.

  IF lt_update IS NOT INITIAL.
    MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
      ENTITY Item UPDATE FIELDS ( TobeBilledQty )
                  WITH lt_update
      REPORTED DATA(lt_rep).
  ENDIF.

  READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
    ENTITY Header ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(lt_final).
  result = VALUE #( FOR h IN lt_final ( %tky = h-%tky %param = h ) ).

ENDMETHOD.

METHOD calcQuantities.

    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
      ENTITY Item ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    DATA lt_update TYPE TABLE FOR UPDATE ZHSN_I_ProjItm.

    LOOP AT lt_items INTO DATA(ls_item).

      " carried-forward consumed = the highest Consumed already saved
      " for this Project + WorkPackage (from previous entries)
      SELECT MAX( consumed_quantity )
        FROM zhsn_proj_itm
        WHERE project_id     = @ls_item-ProjectID
          AND workpackage_id = @ls_item-WorkPackageID
          AND item_uuid     <> @ls_item-ItemUuid
        INTO @DATA(lv_prev_consumed).

      " new consumed = history + what the user is billing now
      DATA(lv_consumed) = lv_prev_consumed + ls_item-TobeBilledQty.

      " balance = total from API - consumed
      DATA(lv_balance) = ls_item-UnitQty - lv_consumed.

      APPEND VALUE #(
        %tky        = ls_item-%tky
        ConsumeQty  = lv_consumed
        BalnacedQty = lv_balance
      ) TO lt_update.

    ENDLOOP.

    IF lt_update IS NOT INITIAL.
      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
        ENTITY Item UPDATE FIELDS ( ConsumeQty BalnacedQty )
                    WITH lt_update
        REPORTED DATA(lt_rep).
    ENDIF.

  ENDMETHOD.


  METHOD validateOverBilling.

    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
      ENTITY Item ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    LOOP AT lt_items INTO DATA(ls_item).

SELECT MAX( consumed_quantity )
        FROM zhsn_proj_itm
        WHERE project_id     = @ls_item-ProjectID
          AND workpackage_id = @ls_item-WorkPackageID
          AND item_uuid     <> @ls_item-ItemUuid
        INTO @DATA(lv_prev_consumed).

      DATA(lv_consumed) = lv_prev_consumed + ls_item-TobeBilledQty.

      " negative check
      IF ls_item-TobeBilledQty < 0.
        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-item.
        APPEND VALUE #( %tky = ls_item-%tky
          %element-TobeBilledQty = if_abap_behv=>mk-on
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text = 'To Be Billed Qty cannot be negative' ) ) TO reported-item.
        CONTINUE.
      ENDIF.

      " over-billing check: consumed must not exceed total
      IF lv_consumed > ls_item-UnitQty.
        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-item.
        APPEND VALUE #( %tky = ls_item-%tky
          %element-TobeBilledQty = if_abap_behv=>mk-on
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text = |Over-billing: consumed { lv_consumed } exceeds total { ls_item-UnitQty }| ) )
          TO reported-item.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.





  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD getProjectData.

    " 1. read ProjectID from the current draft
    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
      ENTITY Header FIELDS ( ProjectID ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_headers).

    " 2. delete existing children first (safe re-run)
*    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*      ENTITY Header BY \_Item FIELDS ( ItemUuid ) WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_existing).
*
*    IF lt_existing IS NOT INITIAL.
*      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
*        ENTITY Item DELETE FROM VALUE #( FOR e IN lt_existing ( %tky = e-%tky ) )
*        REPORTED DATA(lt_rep_del).
*    ENDIF.

" read work packages already on this project (so we don't duplicate them)
    READ ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
      ENTITY Header BY \_Item FIELDS ( WorkPackageID ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_existing_items).

    DATA lt_hdr_update TYPE TABLE FOR UPDATE ZHSN_I_ProjHdr.
    DATA lt_create_by  TYPE TABLE FOR CREATE ZHSN_I_ProjHdr\_Item.

    LOOP AT lt_headers INTO DATA(ls_hdr).

      IF ls_hdr-ProjectID IS INITIAL.
        APPEND VALUE #( %tky = ls_hdr-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text = 'Select a Project ID first' ) ) TO reported-header.
        CONTINUE.
      ENDIF.

      TRY.
          NEW zcl_hsn_proj_api_reader( )->get_project_by_id(
            EXPORTING iv_project_id = CONV #( ls_hdr-ProjectID )
            IMPORTING es_project = DATA(ls_api) ev_found = DATA(lv_found) ).
        CATCH cx_web_http_client_error cx_http_dest_provider_error INTO DATA(lx).
          APPEND VALUE #( %tky = ls_hdr-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text = |API failed: { lx->get_text( ) }| ) ) TO reported-header.
          CONTINUE.
      ENDTRY.

      IF lv_found = abap_false.
        APPEND VALUE #( %tky = ls_hdr-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-warning
                   text = |No project found for { ls_hdr-ProjectID }| ) ) TO reported-header.
        CONTINUE.
      ENDIF.

      " 3. header field update
      APPEND VALUE #(
        %tky = ls_hdr-%tky
        ProjectName = ls_api-projectname   ProjectStage = ls_api-projectstage
        OrgID = ls_api-orgid               Currency = ls_api-currency
        Customer = ls_api-customer         CostCenter = ls_api-costcenter
        ProfitCenter = ls_api-profitcenter StartDate = ls_api-startdate
        EndDate = ls_api-enddate           ProjectDesc = ls_api-projectdesc
      ) TO lt_hdr_update.

      " 4. create-by-association — carry the draft flag onto parent ref and children
*      APPEND VALUE #(
*        %tky-ProjUuid  = ls_hdr-%tky-ProjUuid
*        %tky-%is_draft = ls_hdr-%tky-%is_draft
*        %target = VALUE #( FOR ls_wp IN ls_api-workpackages INDEX INTO i (
*                    %cid            = |WP{ i }_{ ls_hdr-%tky-ProjUuid }|
*                    %is_draft       = ls_hdr-%tky-%is_draft
*                    ProjectID       = ls_wp-projectid
*                    WorkPackageID   = ls_wp-workpackageid
*                    WorkPackageName = ls_wp-workpackagename
*                    Description     = ls_wp-description
*                    WPStartDate     = ls_wp-wpstartdate
*                    WPEndDate       = ls_wp-wpenddate
*                    UnitQty         = ls_wp-unitquantity ) )
*      ) TO lt_create_by.
*
*    ENDLOOP.

" 4. create-by-association — only ADD work packages not already present
      DATA lt_new_wp LIKE ls_api-workpackages.
      CLEAR lt_new_wp.

      LOOP AT ls_api-workpackages INTO DATA(ls_wp_chk).
        " skip if this WorkPackageID is already a line on the project
        IF NOT line_exists( lt_existing_items[ WorkPackageID = ls_wp_chk-workpackageid ] ).
          APPEND ls_wp_chk TO lt_new_wp.
        ENDIF.
      ENDLOOP.

      IF lt_new_wp IS NOT INITIAL.
        APPEND VALUE #(
          %tky-ProjUuid  = ls_hdr-%tky-ProjUuid
          %tky-%is_draft = ls_hdr-%tky-%is_draft
          %target = VALUE #( FOR ls_wp IN lt_new_wp INDEX INTO i (
                      %cid            = |WP{ i }_{ ls_hdr-%tky-ProjUuid }|
                      %is_draft       = ls_hdr-%tky-%is_draft
                      ProjectID       = ls_wp-projectid
                      WorkPackageID   = ls_wp-workpackageid
                      WorkPackageName = ls_wp-workpackagename
                      Description     = ls_wp-description
                      WPStartDate     = ls_wp-wpstartdate
                      WPEndDate       = ls_wp-wpenddate
                      UnitQty         = ls_wp-unitquantity ) )
        ) TO lt_create_by.
      ENDIF.

    " 5a. header update
    IF lt_hdr_update IS NOT INITIAL.
      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
        ENTITY Header UPDATE FIELDS ( ProjectName ProjectStage OrgID Currency Customer
                                      CostCenter ProfitCenter StartDate EndDate ProjectDesc )
                      WITH lt_hdr_update
        REPORTED DATA(lt_rep_upd).
    ENDIF.

    ENDLOOP.

" 5b. create children
    IF lt_create_by IS NOT INITIAL.
      MODIFY ENTITIES OF ZHSN_I_ProjHdr IN LOCAL MODE
        ENTITY Header CREATE BY \_Item FIELDS ( ProjectID WorkPackageID WorkPackageName
                                                Description WPStartDate WPEndDate UnitQty )
                      WITH lt_create_by
        REPORTED DATA(lt_rep_cre).
    ENDIF.

  ENDMETHOD.

ENDCLASS.
