@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value Help CDS'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZHSN_CUST_CDS as select from I_EnterpriseProject
{
      @Search.defaultSearchElement: true
  key Project,
      ProjectInternalID,
      ProjectDescription
}
