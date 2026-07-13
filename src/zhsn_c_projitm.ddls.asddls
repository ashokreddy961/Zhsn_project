@EndUserText.label: 'Project Item - Projection'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
define view entity ZHSN_C_ProjItm
  as projection on ZHSN_I_ProjItm
{
  key ItemUuid,
  ProjUuid,
  ProjectID,
  WorkPackageID,
  WorkPackageName,
  Description,
  WPStartDate,
  WPEndDate,
  UnitQty,
  ConsumeQty,
  BalnacedQty,
  TobeBilledQty,
  LastChangedAt,
  LocalLastChangedAt,
  /* Associations */
  _Header:redirected to parent ZHSN_C_ProjHdr
}
      
