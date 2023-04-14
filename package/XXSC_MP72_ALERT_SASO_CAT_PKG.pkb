CREATE OR REPLACE PACKAGE BODY APPS.XXSC_MP72_ALERT_SASO_CAT_PKG
AS
/***************************************************************************************************
 *                                                                                                 *
 *  PROJECT       MARAZZI - Oracle Applications                                                    *
 *                                                                                                 *
 *  DESCRIPTION   MP72 Programma di Alert SASO Category                                            *
 *                                                                                                 *
 *                                                                                                 *
 *  HISTORY:                                                                                       *
 *                                                                                                 *
 *  Version  Date         Author           Description                                             *
 *  -------  -----------  ---------------  ------------------------------------------------------  *
 *  1.0      27/03/2023   P.Interlandi    Creation - ERP-2469                                      *
 *  1.1      06/04/2023   P.Interlandi    Correzione Alert SASO 1 ERP-2479                         *
 ***************************************************************************************************/
---------------------------
-- LOG
---------------------------
PROCEDURE TO_LOG (p_msg IN VARCHAR2)
IS
  l_msg          VARCHAR2(32767);
  l_debug_level  NUMBER := TO_NUMBER(NVL(fnd_profile.value('XXFD_DEBUG_LEVEL'), '0'));
BEGIN
  IF l_debug_level > 0 THEN
    l_msg := SUBSTR(TO_CHAR (SYSDATE, 'HH24:MI:SS') || ': ' || p_msg, 1,4000);
    fnd_file.put_line (fnd_file.LOG, l_msg);
  END IF;
END TO_LOG;


PROCEDURE CREATE_TEMP (errbuf      OUT VARCHAR2
                      ,retcode     OUT VARCHAR2
                      ,p_msg IN VARCHAR2)
IS
  l_msg              VARCHAR2(32767);
  l_debug_level      NUMBER := TO_NUMBER(NVL(fnd_profile.value('XXFD_DEBUG_LEVEL'), '0'));
  l_conc_request_id  NUMBER := fnd_global.conc_request_id;
BEGIN
  TO_LOG('Start CREATE_TEMP '||TO_CHAR(SYSDATE,'dd/mm/yyyy hh24:mi:ss')||' - l_conc_request_id: '||l_conc_request_id);
  retcode := 0;
  errbuf  := NULL;
  
--STEP1
--msi  xxsc_mp72_msi_tmp rows: 49.022 time: 00:00:10 sec
INSERT INTO apps.xxsc_mp72_msi_tmp  
SELECT msi.item_type
     , flvit.meaning ITEM_TYPE_DESC
     , msi.organization_id
     , msi.inventory_item_status_code
     , mis.inventory_item_status_code_tl ITEM_STATUS_CODE_TL
     , msi.inventory_item_id
     , msi.segment1
     , mitl.description DESCRIPTION
     , SUBSTR(mitl.long_description,1,2000) LONG_DESCRIPTION     
FROM apps.mtl_system_items_b msi
    ,apps.fnd_lookup_values flvit
    ,apps.mtl_system_items_tl mitl
    ,apps.mtl_item_status  mis
WHERE msi.organization_id = 84
AND msi.inventory_item_status_code = mis.inventory_item_status_code --IN ('00','12','18','13','10','20','30','05','11')
AND mis.inventory_item_status_code IN ('00','05','10','11','12','13','18','20','30')
AND mis.DISABLE_DATE IS NULL 
AND flvit.lookup_type = 'ITEM_TYPE'
AND flvit.language = 'I' 
AND mitl.inventory_item_id = msi.inventory_item_id
AND mitl.organization_id   = msi.organization_id
AND mitl.language          = 'US'  --USERENV ('LANG')  
AND msi.item_type IN ('MG_PF','MG_PC')  
AND flvit.lookup_code = msi.item_type;
TO_LOG('INSERT INTO XXSC_MP72_MSI_TMP: '||SQL%ROWCOUNT);
           
--esi
--STEP2
--esi rows: 40747
INSERT INTO apps.xxsc_mp72_esi_tmp   
SELECT apc.C_Ext_Attr6 --Codice tipologia Serie
     , apc.c_ext_attr9 --Codice classificazione norma EN 87
     , apc.C_Ext_Attr20 --Flag a Catalogo
     , apc.inventory_item_id
     , ffvEN87.flex_value_meaning  gruppo_en_87_desc
     , evs.description             cod_tipol_serie
     , evs.internal_name           internal_name
  FROM apps.ego_mtl_sy_items_ext_b apc,
       apps.fnd_flex_values_vl     ffven87,
       apps.ego_value_set_values_v evs,
       apps.xxsc_mp72_msi_tmp      msi
WHERE  apc.inventory_item_id        = msi.inventory_item_id
   AND apc.organization_id          = msi.organization_id
   AND apc.organization_id(+)       = 84
   AND apc.item_catalog_group_id(+) <> -1
   AND apc.attr_group_id(+)         <> 2
   AND apc.c_ext_attr6              <> '19'--SEMI-FINISHED 
   AND ffven87.flex_value_set_id(+) = 1014224
   AND ffven87.flex_value(+)        = apc.c_ext_attr9
   AND evs.enabled_code             = 'Y'
   AND evs.value_set_id             = 1014227
   AND evs.internal_name            = apc.c_ext_attr6; 
TO_LOG('INSERT INTO XXSC_MP72_ESI_TMP: '||SQL%ROWCOUNT);   

--STEP3 todos los articulos con la categoria saso creada
--cat_saso MG_SASO
INSERT INTO apps.xxsc_mp72_cat_saso_tmp 
SELECT DISTINCT mc.segment1,mct.description , --Processing type
	mic.inventory_item_id,mic.organization_id
FROM apps.mtl_item_categories mic, 
	 apps.mtl_categories_b mc,
	 apps.mtl_categories_tl   mct
WHERE     1=1
	 --AND mic.organization_id = saso_org.org_id
	 AND mic.category_set_id = 1100000643 --MG_SASO
	 AND (STRUCTURE_ID = 51175)                  
	 AND mc.category_id = mct.category_id
	 AND mct.language = 'US' --USERENV ('LANG')
	 AND mc.category_id = mic.category_id;
TO_LOG('INSERT INTO XXSC_MP72_CAT_SASO_TMP: '||SQL%ROWCOUNT);    

--STEP4 Todos los articulos STEP1 + Categoria MG Inventory Categories 
--cat MG Inventory Categories rows 48945 0:07 sec
INSERT INTO apps.xxsc_mp72_cat_tmp 
SELECT mc.segment1
     , mc.segment2
     , mc.segment3
     , mc.segment4 --Brand
     , ffv.attribute5  rectified
     , mic.inventory_item_id
  FROM apps.mtl_item_categories mic 
     , apps.mtl_categories_kfv  mc
     , apps.fnd_flex_values_vl  ffv
     , apps.xxsc_mp72_msi_tmp   msi
WHERE mic.organization_id = 84
   AND mic.category_set_id = 1100000061
   AND mc.category_id = mic.category_id
   AND mic.inventory_item_id = msi.inventory_item_id
   AND ffv.flex_value_set_id = 1013681
   AND mc.segment1 = ffv.flex_value
   AND mc.segment3 NOT IN ('ZE-04','ZD-04','DU-66','DX-66','ZF-04');
TO_LOG('INSERT INTO XXSC_MP72_CAT_TMP: '||SQL%ROWCOUNT); 
	MDHD-97913 Estrazione collegamento decoro>fondo 
--STEP5 todos los articulos --STEP1 + Categoria MG Tipo di Lavorazione
--tipo_lav
INSERT INTO apps.XXSC_MP72_TIPO_LAV_TMP
SELECT mc.segment1
     , mct.description
     , mic.inventory_item_id
   --, DECODE(mc.segment1,'50',mc.segment1,'*all') decoro --ERP-2479
	 , DECODE(mc.segment1,'53',mc.segment1,'*all') decoro --ERP-2479
  FROM apps.mtl_item_categories mic
     , apps.mtl_categories_kfv  mc
     , apps.mtl_categories_tl   mct
     , apps.xxsc_mp72_msi_tmp   msi
WHERE mic.organization_id = 84
   AND mic.category_set_id = 1100000086 --MG Tipo di Lavorazione
   AND STRUCTURE_ID=50373
   AND mc.category_id = mct.category_id
   AND mic.inventory_item_id = msi.inventory_item_id
   AND mct.language = 'US'--USERENV ('LANG')
   AND mc.category_id = mic.category_id;
TO_LOG('INSERT INTO XXSC_MP72_TIPO_LAV_TMP: '||SQL%ROWCOUNT); 


--STEP6 todos los articulos --STEP1 + Categoria MG Spessori
--spessori
INSERT INTO apps.XXSC_MP72_SPESSORI_TMP  
SELECT mc.segment1
     , mic.inventory_item_id 
  FROM apps.mtl_item_categories  mic
     , apps.mtl_categories_kfv   mc
     , apps.xxsc_mp72_msi_tmp   msi
WHERE mic.organization_id   = 84
   AND mic.category_set_id   = 1100000085
   AND mic.inventory_item_id = msi.inventory_item_id
   AND mc.category_id        = mic.category_id;
TO_LOG('INSERT INTO XXSC_MP72_SPESSORI_TMP: '||SQL%ROWCOUNT);

--STEP7 todos los articulos --STEP1 + Categoria MG Sourcing Assignment
--sourcing_assignment
INSERT INTO apps.XXSC_MP72_SOURCING_ASSIGNMENT_TMP
SELECT mc.segment1
     , mic.inventory_item_id
     , mc.category_id
     , DECODE(mc.attribute4,'1','Make',2,'Buy') MOB
     , mc.attribute4 MOB_CODE
     , mc.attribute1 country  
  FROM apps.mtl_item_categories mic, 
       apps.mtl_categories_kfv mc,
       apps.xxsc_mp72_msi_tmp   msi
WHERE mic.organization_id = 84
   AND mic.category_set_id = 1100000068 
   AND mc.category_id = mic.category_id
   AND mic.inventory_item_id = msi.inventory_item_id;

TO_LOG('INSERT INTO XXSC_MP72_SOURCING_ASSIGNMENT_TMP: '||SQL%ROWCOUNT);

--STEP8 todos los articulos --STEP1 + Categoria MG Formati Prodotti Finiti
--Formato
INSERT INTO apps.xxsc_mp72_formati_tmp 
SELECT mc.segment1
     , mct.description Dimension_code
     , mc.category_id Dimension_id
     , mic.inventory_item_id
     , mc.SEGMENT1     Lunghezza
     , mc.SEGMENT2     Larghezza
FROM apps.mtl_item_categories mic
   , apps.mtl_categories_kfv mc
   , apps.mtl_categories_tl mct
   , apps.xxsc_mp72_msi_tmp   msi
WHERE mic.organization_id = 84
  AND mic.category_set_id   = 1100000082 --MG Formati Prodotti Finiti
  AND STRUCTURE_ID          = 50369
  AND mc.category_id        = mct.category_id
  AND mct.language          = 'US' --USERENV ('LANG')
  AND mc.category_id        = mic.category_id
  AND mic.inventory_item_id = msi.inventory_item_id
  AND mc.category_id NOT IN (18579,995214); -- 000x000 001x001  1.1 ERP-2479
  
TO_LOG('INSERT INTO XXSC_MP72_FORMATI_TMP: '||SQL%ROWCOUNT);     

--STEP9
--saso_rules
INSERT INTO apps.xxsc_mp72_saso_rules_tmp
SELECT item_type
     , brand
     , gruppo_en_87
     , decoro
     , make_buy
  FROM APPS.xxsc_mp72_sasorules
WHERE (SYSDATE >= start_date_active OR start_date_active IS NULL)
   AND (SYSDATE <= end_date_active OR end_date_active IS NULL)
   AND NVL(enabled_flag,'Y') ='Y'
   AND UPPER(nazione_prod)  IN ('IT','ES')
   AND make_buy = 1;
TO_LOG('INSERT INTO XXSC_MP72_SASO_RULES_TMP: '||SQL%ROWCOUNT);    

--STEP10
INSERT INTO APPS.xxsc_mp72_eancode_tmp
SELECT COD_EAN,BRAND,GRUPPO_EN_87,RECTIFIED,DIMENSION_ID
            FROM APPS.XXSC_MP72_EANCODE SASOEAN
            WHERE 1=1
            AND NVL(enabled_flag,'Y') ='Y'
            AND (SYSDATE >= start_date_active OR start_date_active IS NULL)
            AND (SYSDATE <= end_date_active OR end_date_active IS NULL);
TO_LOG('INSERT INTO XXSC_MP72_EANCODE_TMP: '||SQL%ROWCOUNT); 

--STEP11
INSERT INTO  APPS.xxsc_mp72_org_saso_tmp
SELECT so.saso_org_id,
       so.sourcing_id,
	   so.saso_org_code,
	   so.saso_org_desc 
FROM apps.xxsc_mp72_sasoorg so                                
WHERE so.enabled_flag='Y'
AND (SYSDATE >= so.start_date_active OR so.start_date_active IS NULL)
AND (SYSDATE <= so.end_date_active OR so.end_date_active IS NULL);
TO_LOG('INSERT INTO XXSC_MP72_ORG_SASO_TMP: '||SQL%ROWCOUNT); 

--Inser alert
--STEP-FINAL1
INSERT INTO apps.xxsc_mp72_alert_saso_tmp
SELECT DISTINCT
 'CATEGORIA SASO MANCANTE'                              controllo_categoria_saso
,'INSERIRE CATEGORIA MG_SASO'                           azione_richiesta
,cs.cod_ean                                             codice_saso
,'Crea'                                                 webadi_tipoditransazione
,so.saso_org_code                                       webadi_codiceorganizzazione
,msi.segment1                                           webadi_articolo
,'MG_SASO'                                              webadi_catalogo
,cs.cod_ean                                             webadi_categoria
,NULL                                                   webadi_categoriaprecedente
,NULL                                                   mp72_brand
,NULL                                                   mp72_brand_desc
,NULL                                                   mp72_en87
,NULL                                                   mp72_en87_desc
,NULL                                                   mp72_dimension_code
,NULL                                                   mp72_rectified
,NULL                                                   mp72_processing_type_rule
,NVL(so.saso_org_code,'SOURCING/ORG '||asg.segment1||' NON PRESENTE MP72_SASOORG') saso_org_code
,NULL                                                   item_code
,NULL                                                   description
,NULL                                                   long_description
,NULL                                                   item_type_desc
,NULL                                                   item_status_code_tl
FROM apps.xxsc_mp72_msi_tmp msi,
     apps.xxsc_mp72_esi_tmp esi,
     xxsc_mp72_cat_tmp cat,
     apps.xxsc_mp72_tipo_lav_tmp lav,
     apps.xxsc_mp72_sourcing_assignment_tmp asg,
     apps.xxsc_mp72_formati_tmp fmt,
     APPS.xxsc_mp72_org_saso_tmp  so,
     apps.xxsc_mp72_saso_rules_tmp sr,
     APPS.xxsc_mp72_eancode_tmp cs
WHERE 1=1
AND esi.inventory_item_id = msi.inventory_item_id
AND cat.inventory_item_id = msi.inventory_item_id
AND lav.inventory_item_id = msi.inventory_item_id
AND asg.inventory_item_id = msi.inventory_item_id
AND fmt.inventory_item_id = msi.inventory_item_id
--Existe Saso_org configurada
AND asg.category_id = so.sourcing_id
--articoli senza catagoria saso
--MG_SASO = null
AND NOT EXISTS (SELECT 1 FROM apps.xxsc_mp72_cat_saso_tmp cat_saso WHERE cat_saso.inventory_item_id = msi.inventory_item_id)
--Ha i requisiti SASO
AND sr.item_type=msi.item_type --MG_PC
AND sr.brand=cat.segment4 --01
AND sr.gruppo_en_87= esi.c_ext_attr9 --en87 --06
AND sr.decoro=lav.decoro --*all
AND sr.make_buy=asg.mob_code --1
--Esiste il codice SASO da assegnare
AND cs.BRAND = cat.segment4
AND cs.GRUPPO_EN_87 = esi.c_ext_attr9 
AND cs.RECTIFIED = cat.rectified
AND cs.DIMENSION_ID = fmt.Dimension_id;
TO_LOG('INSERT INTO XXSC_MP72_ALERT_SASO_TMP STEP-FINAL1: '||SQL%ROWCOUNT); 

--STEP-FINAL2
INSERT INTO  APPS.xxsc_mp72_alert_saso_tmp
SELECT DISTINCT
 'CATEGORIA SASO MANCANTE'                              controllo_categoria_saso
,'CREARE CODICE SASO IN TABELLA MP72 Saso Quality Mark E INSERIRE CATEGORIA MG_SASO'                           azione_richiesta
,'DA DEFINIRE'                                          codice_saso
,'Configurazione'                                       webadi_tipoditransazione
,NULL                                                   webadi_codiceorganizzazione
,NULL                                                   webadi_articolo
,NULL                                                   webadi_catalogo
,NULL                                                   webadi_categoria
,NULL                                                   webadi_categoriaprecedente
,cat.segment4                                           mp72_brand
,branddesc.description                                  mp72_brand_desc
,esi.c_ext_attr9                                        mp72_en87
,esi.gruppo_en_87_desc                                  mp72_en87_desc
,fmt.dimension_code                                     mp72_dimension_code
,cat.rectified                                          mp72_rectified
,lav.decoro                                             mp72_processing_type_rule
,so.saso_org_code                                       saso_org_code
,msi.segment1                                           item_code
,msi.description                                        description
,msi.long_description                                   long_description
,msi.item_type_desc                                     item_type_desc
,msi.item_status_code_tl                                item_status_code_tl 
FROM apps.xxsc_mp72_msi_tmp msi,
     apps.xxsc_mp72_esi_tmp esi,
     xxsc_mp72_cat_tmp cat,
     apps.xxsc_mp72_tipo_lav_tmp lav,
     apps.xxsc_mp72_sourcing_assignment_tmp asg,
     apps.xxsc_mp72_formati_tmp fmt,
     APPS.xxsc_mp72_org_saso_tmp  so,
     apps.xxsc_mp72_saso_rules_tmp sr,
     (SELECT flex_value, description
                FROM apps.fnd_flex_values_vl
               WHERE flex_value_set_id = 1013684) 
                     branddesc
WHERE 1=1
AND esi.inventory_item_id = msi.inventory_item_id
AND cat.inventory_item_id = msi.inventory_item_id
AND lav.inventory_item_id = msi.inventory_item_id
AND asg.inventory_item_id = msi.inventory_item_id
AND fmt.inventory_item_id = msi.inventory_item_id
--
AND branddesc.flex_value(+) = cat.segment4  
--Existe Saso_org configurada
AND asg.category_id = so.sourcing_id
--articoli senza catagoria saso
--MG_SASO = null
AND NOT EXISTS (SELECT 1 FROM apps.xxsc_mp72_cat_saso_tmp cat_saso WHERE cat_saso.inventory_item_id = msi.inventory_item_id)
--Ha i requisiti SASO
AND sr.item_type=msi.item_type --MG_PC
AND sr.brand=cat.segment4 --01
AND sr.gruppo_en_87= esi.c_ext_attr9 --en87 --06
AND sr.decoro=lav.decoro --*all
AND sr.make_buy=asg.mob_code --1
--NON Esiste il codice SASO da assegnare
AND NOT EXISTS (SELECT 1 
                FROM  APPS.xxsc_mp72_eancode_tmp cs
                WHERE cs.BRAND = cat.segment4
                AND cs.GRUPPO_EN_87 = esi.c_ext_attr9 
                AND cs.RECTIFIED = cat.rectified
                AND cs.DIMENSION_ID = fmt.Dimension_id);
TO_LOG('INSERT INTO XXSC_MP72_ALERT_SASO_TMP STEP-FINAL2: '||SQL%ROWCOUNT); 

--STEP-FINAL3
INSERT INTO  APPS.xxsc_mp72_alert_saso_tmp
SELECT DISTINCT
--output
 'CATEGORIA SASO ERRATA'                                controllo_categoria_saso
,'AGGIORNARE CATEGORIA MG_SASO'                         azione_richiesta
,cs.cod_ean                                             codice_saso
,'Aggiorna'                                             webadi_tipoditransazione
,so.saso_org_code                                       webadi_codiceorganizzazione
,msi.segment1                                           webadi_articolo
,'MG_SASO'                                              webadi_catalogo
,cs.cod_ean                                             webadi_categoria
,cat_saso.segment1                                      webadi_categoriaprecedente
,cat.segment4                                           mp72_brand
,branddesc.description                                  mp72_brand_desc
,esi.c_ext_attr9                                        mp72_en87
,esi.gruppo_en_87_desc                                  mp72_en87_desc
,fmt.dimension_code                                     mp72_dimension_code
,cat.rectified                                          mp72_rectified
,lav.decoro                                             mp72_processing_type_rule
,so.saso_org_code                                       saso_org_code
,msi.segment1                                           item_code
,msi.description                                        description
,msi.long_description                                   long_description
,msi.item_type_desc                                     item_type_desc
,msi.item_status_code_tl                                item_status_code_tl
FROM apps.xxsc_mp72_msi_tmp msi,
     apps.xxsc_mp72_esi_tmp esi,
     xxsc_mp72_cat_tmp cat,
     apps.xxsc_mp72_tipo_lav_tmp lav,
     apps.xxsc_mp72_sourcing_assignment_tmp asg,
     apps.xxsc_mp72_formati_tmp fmt,
     APPS.xxsc_mp72_org_saso_tmp  so,
     apps.xxsc_mp72_saso_rules_tmp sr,
     apps.xxsc_mp72_eancode_tmp cs,
     apps.xxsc_mp72_cat_saso_tmp cat_saso,
     (SELECT flex_value, description
                FROM apps.fnd_flex_values_vl
               WHERE flex_value_set_id = 1013684) 
                     branddesc
WHERE 1=1
AND esi.inventory_item_id = msi.inventory_item_id
AND cat.inventory_item_id = msi.inventory_item_id
AND lav.inventory_item_id = msi.inventory_item_id
AND asg.inventory_item_id = msi.inventory_item_id
AND fmt.inventory_item_id = msi.inventory_item_id
--
AND branddesc.flex_value = cat.segment4  
--Existe Saso_org configurada
AND asg.category_id = so.sourcing_id
--articoli senza catagoria saso
--MG_SASO <> null
AND cat_saso.inventory_item_id = msi.inventory_item_id
--MP72_SASO<>CAT_SASO
AND cs.cod_ean <> cat_saso.segment1
--Ha i requisiti SASO
AND sr.item_type=msi.item_type --MG_PC
AND sr.brand=cat.segment4 --01
AND sr.gruppo_en_87= esi.c_ext_attr9 --en87 --06
AND sr.decoro=lav.decoro --*all
AND sr.make_buy = asg.mob_code --1
--Esiste il codice SASO da assegnare
AND cs.BRAND = cat.segment4
AND cs.GRUPPO_EN_87 = esi.c_ext_attr9 
AND cs.RECTIFIED = cat.rectified
AND cs.DIMENSION_ID = fmt.Dimension_id;
TO_LOG('INSERT INTO XXSC_MP72_ALERT_SASO_TMP STEP-FINAL3: '||SQL%ROWCOUNT); 

--STEP-FINAL4
INSERT INTO  APPS.xxsc_mp72_alert_saso_tmp
SELECT DISTINCT
--output
 'CATEGORIA SASO ERRATA'                                controllo_categoria_saso
,'CANCELLARE CATEGORIA MG_SASO'                         azione_richiesta
,'DA CANCELLARE: '||cat_saso.segment1                   codice_saso
,'Elimina'                                              webadi_tipoditransazione
,so.saso_org_code                                       webadi_codiceorganizzazione
,msi.segment1                                           webadi_articolo
,'MG_SASO'                                              webadi_catalogo
,cat_saso.segment1                                      webadi_categoria
,cat_saso.segment1                                      webadi_categoriaprecedente
,cat.segment4                                           mp72_brand
,branddesc.description                                  mp72_brand_desc
,esi.c_ext_attr9                                        mp72_en87
,esi.gruppo_en_87_desc                                  mp72_en87_desc
,fmt.dimension_code                                     mp72_dimension_code
,cat.rectified                                          mp72_rectified
,lav.decoro                                             mp72_processing_type_rule
,so.saso_org_code                                       saso_org_code
,msi.segment1                                           item_code
,msi.description                                        description
,msi.long_description                                   long_description
,msi.item_type_desc                                     item_type_desc
,msi.item_status_code_tl                                item_status_code_tl
FROM apps.xxsc_mp72_msi_tmp msi,
     apps.xxsc_mp72_esi_tmp esi,
     xxsc_mp72_cat_tmp cat,
     apps.xxsc_mp72_tipo_lav_tmp lav,
     apps.xxsc_mp72_sourcing_assignment_tmp asg,
     apps.xxsc_mp72_formati_tmp fmt,
     APPS.xxsc_mp72_org_saso_tmp  so,
     --apps.xxsc_mp72_saso_rules_tmp sr,
     apps.xxsc_mp72_eancode_tmp cs,
     apps.xxsc_mp72_cat_saso_tmp cat_saso,
     (SELECT flex_value, description
                FROM apps.fnd_flex_values_vl
               WHERE flex_value_set_id = 1013684) 
                     branddesc
WHERE 1=1
AND esi.inventory_item_id = msi.inventory_item_id
AND cat.inventory_item_id = msi.inventory_item_id
AND lav.inventory_item_id = msi.inventory_item_id
AND asg.inventory_item_id = msi.inventory_item_id
AND fmt.inventory_item_id = msi.inventory_item_id
--
AND branddesc.flex_value = cat.segment4  
--Existe Saso_org configurada
AND asg.category_id = so.sourcing_id
--articoli senza catagoria saso
--MG_SASO <> null
AND cat_saso.inventory_item_id = msi.inventory_item_id
--NO Ha i requisiti SASO
AND NOT EXISTS (SELECT 1 FROM apps.xxsc_mp72_saso_rules_tmp sr
                WHERE sr.item_type=msi.item_type --MG_PC
                AND sr.brand=cat.segment4 --01
                AND sr.gruppo_en_87= esi.c_ext_attr9 --en87 --06
                AND sr.decoro=lav.decoro --*all
                AND sr.make_buy = asg.mob_code --1
                )
--Esiste il codice SASO da assegnare
AND cs.BRAND(+) = cat.segment4
AND cs.GRUPPO_EN_87(+) = esi.c_ext_attr9 
AND cs.RECTIFIED(+) = cat.rectified
AND cs.DIMENSION_ID(+) = fmt.Dimension_id;
TO_LOG('INSERT INTO XXSC_MP72_ALERT_SASO_TMP STEP-FINAL4: '||SQL%ROWCOUNT);
                                    
EXCEPTION
  WHEN OTHERS THEN
    retcode := 2;
    TO_LOG ( 'Error Others - Error_Stack...' || CHR(10) ||DBMS_UTILITY.FORMAT_ERROR_STACK());
    TO_LOG ( 'Error_Backtrace...' || CHR(10) ||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());
    ROLLBACK;
END CREATE_TEMP;

--Call from el xml data template
FUNCTION BeforeReport  RETURN BOOLEAN
IS
   l_retcode         NUMBER :=0;
   l_errbuf          VARCHAR2(2000);
   l_msg_data       VARCHAR2(4000);
   l_conc_request_id NUMBER := fnd_global.conc_request_id;
BEGIN
TO_LOG('Ini BeforeReport '||TO_CHAR(SYSDATE,'dd/mm/yyyy hh24:mi:ss')||' - l_conc_request_id: '||l_conc_request_id);
    CREATE_TEMP ( errbuf   => l_errbuf
                 ,retcode  => l_retcode
                 ,p_msg => l_msg_data
                );
TO_LOG('End BeforeReport '||TO_CHAR(SYSDATE,'dd/mm/yyyy hh24:mi:ss')||' - l_conc_request_id: '||l_conc_request_id);
    IF l_retcode = 2 THEN
       ROLLBACK;
       RETURN (FALSE);
    ELSE
        --COMMIT;
        RETURN (TRUE);
    END IF;

EXCEPTION
  WHEN OTHERS THEN
    FND_FILE.put_line( FND_FILE.LOG,'AN ERROR IS ENCOUNTERED IN BEFORE REPORT FUNCTION '|| SQLCODE || 'ERROR ' || SQLERRM);
    RETURN (FALSE);
END BeforeReport;
--Call from el xml data template
FUNCTION AfterReport  RETURN BOOLEAN
IS
l_conc_request_id    NUMBER := fnd_global.conc_request_id;
ln_request_id        NUMBER;
l_phase              VARCHAR2 (50);
l_status             VARCHAR2 (50);
l_dev_phase          VARCHAR2 (50);
l_dev_status         VARCHAR2 (50);
l_message            VARCHAR2 (50);
l_req_return_status  BOOLEAN;

lv_email_address  VARCHAR2 (250);
lv_cc_address     VARCHAR2 (250);
lv_subject_mail   VARCHAR2 (250);
lv_body_mail      VARCHAR2 (150); --

ln_control_alert        NUMBER:=0;
BEGIN

SELECT COUNT(1) INTO ln_control_alert FROM APPS.xxsc_mp72_alert_saso_tmp WHERE ROWNUM=1;

IF ln_control_alert > 0 THEN
TO_LOG('Ini AfterReport '||TO_CHAR(SYSDATE,'dd/mm/yyyy hh24:mi:ss')||' - l_conc_request_id: '||l_conc_request_id);

            lv_email_address   := fnd_profile.value('XXSC_MP72_EMAIL_ADDRESS');    --XXSC: MP72 email address
            lv_cc_address      := fnd_profile.value('XXSC_MP72_EMAIL_CC_ADDRESS'); --XXSC: MP72 CC email address
            lv_subject_mail    := fnd_profile.value('XXSC_MP72_EMAIL_SUBJECT');    --XXSC: MP72 Subject
            lv_body_mail       := fnd_profile.value('XXSC_MP72_EMAIL_BODY');       --XXSC: MP72 email body

/*
In allegato gli articoli che presentano anomalie sulla categoria MG_SASO.
Per l'aggionamento seguire le indicazioni presenti nel file.				
*/

               ln_request_id := fnd_request.submit_request(APPLICATION  =>'XXSC',
                                                           PROGRAM      =>'XXSCOM88DELIVER',
                                                           description  =>'EMAIL: XXSC MP72 Alert SASO CATEGORY',
                                                           start_time   =>'',
                                                           sub_request  =>FALSE,
                                                           argument1    =>'EMAIL',                       -- p_delivery_channel
                                                           argument2    =>NULL,                          -- p_party_type
                                                           argument3    =>NULL,                          -- p_cust_account_id
                                                           argument4    =>NULL,                          -- p_contact_reference
                                                           argument5    =>lv_email_address,              -- p_other_contact_references
                                                           argument6    =>'noreplay@marazzigroup.com',   -- p_from_address
                                                           argument7    =>NULL,                          -- p_cc_address
                                                           argument8    =>lv_subject_mail||' - '||TO_CHAR(SYSDATE,'yyyy-mm-dd hh24:mi:ss'),               -- p_subject
                                                           argument9    =>lv_body_mail,                  -- p_body
                                                           argument10   =>l_conc_request_id,                  -- p_attach
                                                           argument11   =>'0');                          -- p_log_message_level
     COMMIT; --vacia las tablas temporales
     TO_LOG('End AfterReport '||TO_CHAR(SYSDATE,'dd/mm/yyyy hh24:mi:ss')||' - l_conc_request_id: '||l_conc_request_id);          
END IF;
     RETURN (TRUE);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    FND_FILE.put_line( FND_FILE.LOG,'AN ERROR IS ENCOUNTERED IN AFTER REPORT FUNCTION '|| SQLCODE || 'ERROR ' || SQLERRM);
    RETURN (FALSE);
END AfterReport;


END XXSC_MP72_ALERT_SASO_CAT_PKG;
/