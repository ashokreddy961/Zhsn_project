CLASS zcl_hsn_act_alloc_post DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS post_allocation
      EXPORTING ev_status    TYPE string   " SUCCESS / ERROR
                ev_refdoc    TYPE string   " ReferenceDocument from response
                ev_response  TYPE string.  " full response text
ENDCLASS.

CLASS zcl_hsn_act_alloc_post IMPLEMENTATION.

  METHOD post_allocation.

    CLEAR: ev_status, ev_refdoc, ev_response.

    " hardcoded payload (for now)
    DATA(lv_payload) =
      |\{| &&
        |"ControllingArea":"A000",| &&
        |"DocumentDate":"2026-07-10",| &&
        |"PostingDate":"2026-07-10",| &&
        |"_Item":[| &&
          |\{"ReferenceDocumentItem":"1","SenderCostCenter":"18101301",| &&
           |"CostCtrActivityType":"STUPA2","Quantity":10,"BaseUnit":"MIN",| &&
           |"PartnerOrder":"1000040","PersonnelNumber":"0"\},| &&
          |\{"ReferenceDocumentItem":"2","SenderCostCenter":"18101301",| &&
           |"CostCtrActivityType":"LABOR2","Quantity":8,"BaseUnit":"HR",| &&
           |"PartnerOrder":"1000040","PersonnelNumber":"0"\}| &&
        |]| &&
      |\}|.

    DATA(lv_auth) = |Basic { cl_web_http_utility=>encode_base64(
                      unencoded = 'INTEGRATION:UT8BsHhZkz-cPbMRcvCiaMRzqngFlSAQZTxZBvGM' ) }|.

    DATA lv_csrf    TYPE string.
    DATA lv_cookies TYPE string.

    TRY.
        DATA(lo_dest) = cl_http_destination_provider=>create_by_url(
          i_url = 'https://my403545-api.s4hana.cloud.sap' ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination(
          i_destination = lo_dest ).

        " STEP 1: CSRF fetch (GET on the service root)
        DATA(lo_req1) = lo_client->get_http_request( ).
        lo_req1->set_header_fields( VALUE #(
          ( name = 'Authorization' value = lv_auth )
          ( name = 'x-csrf-token'  value = 'Fetch' )
          ( name = 'Accept'        value = 'application/json' ) ) ).
        lo_req1->set_uri_path(
          i_uri_path = '/sap/opu/odata4/sap/api_drctactivityallocation/srvd_a2x/sap/directactivityallocation/0001/' ).
        DATA(lo_resp1) = lo_client->execute( i_method = if_web_http_client=>get ).

        LOOP AT lo_resp1->get_header_fields( ) INTO DATA(ls_h).
          CASE to_lower( ls_h-name ).
            WHEN 'x-csrf-token'. lv_csrf = ls_h-value.
            WHEN 'set-cookie'.
              lv_cookies = COND #( WHEN lv_cookies IS INITIAL THEN ls_h-value
                                   ELSE lv_cookies && '; ' && ls_h-value ).
          ENDCASE.
        ENDLOOP.

        " STEP 2: POST the allocation
        DATA(lo_req2) = lo_client->get_http_request( ).
        lo_req2->set_header_fields( VALUE #(
          ( name = 'Authorization' value = lv_auth )
          ( name = 'Content-Type'  value = 'application/json' )
          ( name = 'Accept'        value = 'application/json' )
          ( name = 'x-csrf-token'  value = lv_csrf )
          ( name = 'Cookie'        value = lv_cookies ) ) ).
        lo_req2->set_uri_path(
          i_uri_path = '/sap/opu/odata4/sap/api_drctactivityallocation/srvd_a2x/sap/directactivityallocation/0001/ActivityAllocation' ).
        lo_req2->set_text( lv_payload ).

        DATA(lo_resp2) = lo_client->execute( i_method = if_web_http_client=>post ).
        DATA(lv_code)  = lo_resp2->get_status( )-code.
        ev_response = lo_resp2->get_text( ).

        IF lv_code = 201.
          ev_status = 'SUCCESS'.
          " extract "ReferenceDocument":"NNNN" from the response
          DATA(lv_p) = find( val = ev_response sub = '"ReferenceDocument":"' ).
          IF lv_p >= 0.
            DATA(lv_s) = lv_p + 21.
            DATA(lv_e) = find( val = ev_response sub = '"' off = lv_s ).
            IF lv_e > lv_s.
              ev_refdoc = substring( val = ev_response off = lv_s len = lv_e - lv_s ).
            ENDIF.
          ENDIF.
        ELSE.
          ev_status = 'ERROR'.
        ENDIF.

      CATCH cx_root INTO DATA(lx).
        ev_status   = 'ERROR'.
        ev_response = lx->get_text( ).
    ENDTRY.

  ENDMETHOD.
ENDCLASS.
