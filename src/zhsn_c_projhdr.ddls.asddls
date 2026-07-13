@EndUserText.label: 'Project Header - Projection'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@Search.searchable: true
define root view entity ZHSN_C_ProjHdr
  provider contract transactional_query
  as projection on ZHSN_I_ProjHdr
{
  key ProjUuid,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZHSN_CUST_CDS', element: 'Project' },
                                           distinctValues: true }]
      ProjectID,
      ProjectName, ProjectStage, OrgID,
      @Semantics.currencyCode: true
      Currency,
      Customer, CostCenter, ProfitCenter, StartDate, EndDate, ProjectDesc,
      LastChangedAt, LocalLastChangedAt,
      Attachment,
      MimeType,
      FileName,
      ReferenceDocument,
  AllocStatus,
  AllocResponse,
      _Item : redirected to composition child ZHSN_C_ProjItm
}
