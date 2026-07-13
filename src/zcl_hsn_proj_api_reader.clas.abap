CLASS zcl_hsn_proj_api_reader DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_wp,
             projectid       TYPE string,
             workpackageid   TYPE string,
             workpackagename TYPE string,
             description     TYPE string,
             wpstartdate     TYPE d,
             wpenddate       TYPE d,
             unitquantity    TYPE p LENGTH 8 DECIMALS 3,
           END OF ty_wp,
           tt_wp TYPE STANDARD TABLE OF ty_wp WITH EMPTY KEY,
           BEGIN OF ty_project,
             projectid    TYPE string, projectname  TYPE string,
             projectstage TYPE string, orgid        TYPE string,
             currency     TYPE string, customer     TYPE string,
             costcenter   TYPE string, profitcenter TYPE string,
             startdate    TYPE d,      enddate      TYPE d,
             projectdesc  TYPE string, workpackages TYPE tt_wp,
           END OF ty_project.

    METHODS get_project_by_id
      IMPORTING iv_project_id TYPE string
      EXPORTING es_project    TYPE ty_project
                ev_found      TYPE abap_bool
      RAISING   cx_web_http_client_error
                cx_http_dest_provider_error.

  PRIVATE SECTION.
    CONSTANTS c_host     TYPE string VALUE 'https://my403545-api.s4hana.cloud.sap'.
    CONSTANTS c_service  TYPE string VALUE '/sap/opu/odata/CPD/SC_PROJ_ENGMT_CREATE_UPD_SRV'.
    CONSTANTS c_user     TYPE string VALUE 'INTEGRATION'.
    CONSTANTS c_password TYPE string VALUE 'UT8BsHhZkz-cPbMRcvCiaMRzqngFlSAQZTxZBvGM'.

    " parse types mirror the JSON keys (matched case-insensitively -> no transformation)
    TYPES: BEGIN OF ty_j_wp,
             projectid TYPE string, workpackageid TYPE string,
             workpackagename TYPE string, description TYPE string,
             wpstartdate TYPE string, wpenddate TYPE string,
             unitquantity TYPE string,
           END OF ty_j_wp,
           BEGIN OF ty_j_wpset,
             results TYPE STANDARD TABLE OF ty_j_wp WITH EMPTY KEY,
           END OF ty_j_wpset,
           BEGIN OF ty_j_proj,
             projectid TYPE string, projectname TYPE string, projectstage TYPE string,
             orgid TYPE string, currency TYPE string, customer TYPE string,
             costcenter TYPE string, profitcenter TYPE string,
             startdate TYPE string, enddate TYPE string, projectdesc TYPE string,
             workpackageset TYPE ty_j_wpset,
           END OF ty_j_proj,
           BEGIN OF ty_j_results,
             results TYPE STANDARD TABLE OF ty_j_proj WITH EMPTY KEY,
           END OF ty_j_results,
           BEGIN OF ty_j_root,
             d TYPE ty_j_results,
           END OF ty_j_root.

    METHODS edm_to_dats IMPORTING iv_edm TYPE string RETURNING VALUE(rv_date) TYPE d.
ENDCLASS.

CLASS zcl_hsn_proj_api_reader IMPLEMENTATION.

  METHOD get_project_by_id.
    CLEAR: es_project, ev_found.

    " 1. destination + client (direct URL, test/demo)
    DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( i_url = c_host ).
    DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( i_destination = lo_dest ).

    " 2. request: Basic auth header + relative path with encoded query
    DATA(lv_auth) = |Basic { cl_web_http_utility=>encode_base64(
                       unencoded = |{ c_user }:{ c_password }| ) }|.

    DATA(lo_request) = lo_client->get_http_request( ).
    lo_request->set_header_fields( VALUE #(
      ( name = 'Authorization' value = lv_auth )
      ( name = 'Accept'        value = 'application/json' ) ) ).

    "  %20 = space, %27 = single quote
    lo_request->set_uri_path( i_uri_path =
      |{ c_service }/ProjectSet?$format=json&$expand=WorkPackageSet| &&
      |&$filter=ProjectID%20eq%20%27{ iv_project_id }%27| ).

    " 3. GET
    DATA(lo_response) = lo_client->execute( i_method = if_web_http_client=>get ).
    DATA(lv_status)   = lo_response->get_status( ).
    DATA(lv_json)     = lo_response->get_text( ).
    lo_client->close( ).

    IF lv_status-code >= 400.
      RETURN.
    ENDIF.

    " 4. parse
    DATA ls_root TYPE ty_j_root.
    xco_cp_json=>data->from_string( lv_json )->write_to( REF #( ls_root ) ).

    READ TABLE ls_root-d-results INTO DATA(ls_p) INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " 5. map header to output
    ev_found = abap_true.
    es_project = VALUE #(
      projectid    = ls_p-projectid       projectname  = ls_p-projectname
      projectstage = ls_p-projectstage    orgid        = ls_p-orgid
      currency     = ls_p-currency        customer     = ls_p-customer
      costcenter   = ls_p-costcenter      profitcenter = ls_p-profitcenter
      startdate    = edm_to_dats( ls_p-startdate )
      enddate      = edm_to_dats( ls_p-enddate )
      projectdesc  = ls_p-projectdesc ).

    " 6. map work packages to output
    LOOP AT ls_p-workpackageset-results INTO DATA(ls_wp).
      APPEND VALUE #(
        projectid       = ls_wp-projectid
        workpackageid   = ls_wp-workpackageid
        workpackagename = ls_wp-workpackagename
        description     = ls_wp-description
        wpstartdate     = edm_to_dats( ls_wp-wpstartdate )
        wpenddate       = edm_to_dats( ls_wp-wpenddate )
        unitquantity    = CONV #( ls_wp-unitquantity )
      ) TO es_project-workpackages.
    ENDLOOP.

  ENDMETHOD.

  METHOD edm_to_dats.
    " input like "/Date(1775001600000)/" or "/Date(1778483869000+0000)/"
    DATA(lv) = iv_edm.
    REPLACE ALL OCCURRENCES OF '/Date(' IN lv WITH ``.
    REPLACE ALL OCCURRENCES OF ')/'     IN lv WITH ``.
    IF lv CA '+'.
      SPLIT lv AT '+' INTO lv DATA(lv_tz).
    ENDIF.
    CONDENSE lv.
    IF lv IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_ms)   = CONV decfloat34( lv ).
    DATA(lv_days) = CONV i( floor( lv_ms / ( 1000 * 60 * 60 * 24 ) ) ).
    rv_date = CONV d( '19700101' ) + lv_days.
  ENDMETHOD.

ENDCLASS.

